class Source < ActiveRecord::Base
  belongs_to :language, :counter_cache => true
  belongs_to :user
  has_many   :links
  has_many   :tags, :through => :links
  has_many   :comments, 
    :foreign_key => :commentable_id, 
    :conditions => [ 'commentable_type = ?', Comment::COMMENTABLE_TYPES[:source] ]

  default_scope :order => "created_at DESC"
  scope :popular, :order => 'views DESC'

  validates :title, presence: true, uniqueness: { case_sensitive: false }, length: { :minimum => 5, :maximum => 255 }
  validates :text, presence: true, length: { :minimum => 25 }
  validate :language_id_exists

  before_create :create_name       # create unique cached slug
  after_save    :lexical_analysis! # extract keywords and their weights
  after_save    :invalidate_highlight_cache!

  self.per_page = 10

  def path
    "/#{language.name}/#{name}.html"
  end

  def url
    "http://www.emoticode.net#{path}"
  end

  def description!
    if !description.nil? && !description.empty?
      description
    else
      title
    end
  end

  def commentable_type
    Comment::COMMENTABLE_TYPES[:source]
  end

  def related( limit = 5 )
    Rails.cache.fetch "#{limit}_related_sources_of_#{id}", :expires_in => 24.hours do
      Source
      .where( 'sources.id != ?', id )
      .joins(:links)
      .where( 'links.tag_id IN ( ? )', links.map(&:tag_id) )
      .order( '( COUNT(links.id) * links.weight ) DESC' )
      .group( 'links.source_id, sources.name' )
      .limit( limit )
      .all
    end
  end

  private

  def create_name
    base_name = title.parameterize
    name = base_name
    counter = 2
    # even if the title is validate for its uniqueness, different
    # titles could be converted to the same slug due to transliterations,
    # therefore we have to make sure that the slug is unique too.
    while Source.find_by_name(name).nil? == false
      name = "#{base_name}-#{counter}"
      counter += 1
    end

    self.name = name
  end

  def lexical_analysis!
    analysis = {}
    base     = 0.5

    # extract meaningful identifiers of at least 4 characters and at most 50, with a css 
    # class starting with a 'n' or a 'v'.
    # ( pygments/token.py )
    tokens = Albino.colorize( text, language.syntax ).scan( /<span\s+class="[nv][^"]*">([^<]{4,50})<\/span>/im ).map(&:first)

    # remove tokens when they are formed by a repetition ( ex. 'aaaaaaaaaa' or '___' )
    tokens.reject! { |token| token.gsub( token[0], '' ).empty? }
    # build a lower case version
    lowerized = tokens.map { |token| token.downcase }

    # build the analysis map where each token weight
    # is given by the formula:
    #
    #   base_weight + 0.3 * ( occurrences(token) - 1 )
    tokens.each do |token|
      unless analysis.has_key? token
        analysis[token] = base + 0.3 * ( lowerized.count( token.downcase ) - 1 )
      end
    end

    # save to db
    analysis.each do |token,weight|
      tag_name = token.parameterize

      # create the tag if it doesn't exist yet
      tag = Tag.find_by_name tag_name

      if tag.nil?
        tag = Tag.create( :name => tag_name, :value => token )
      end

      # create a link with this source if not already present,
      # otherwise increment its weight
      link = Link.find_by_source_id_and_tag_id( id, tag.id )
      
      if link.nil?
        Link.create( :source_id => id, :tag_id => tag.id, :weight => weight )
      else
        link.weight += 0.3
        link.save
      end
    end 
  end

  def invalidate_highlight_cache!
    Rails.cache.delete "highlighted_source_#{id}"
  end

  def language_id_exists
    begin
      Language.find( language_id )
    rescue ActiveRecord::RecordNotFound
      errors.add( :language_id, "is not a valid language id." )
      false
    end
  end
end
