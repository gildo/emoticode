class FacebookClient
  def initialize
    @config = Rails.application.config.secrets['Facebook']
    @graph = Koala::Facebook::API.new @config['token']
  end   

  def post( title, url, image = 'http://www.emoticode.net/logo_2.0_200.png' )
    @graph.put_connections @config['page_id'], 'feed', :message => title, :picture => image, :link => url
  end
end
