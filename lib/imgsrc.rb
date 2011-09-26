#!/usr/bin/env ruby

#############################################################################
#    imgsrc - iMGSRC.RU client                                              #
#    (C) 2011, Vasiliy Yeremeyev <vayerx@gmail.com>                         #
#                                                                           #
#    This program is free software: you can redistribute it and/or modify   #
#    it under the terms of the GNU General Public License as published by   #
#    the Free Software Foundation, either version 3 of the License, or      #
#    (at your option) any later version.                                    #
#                                                                           #
#    This program is distributed in the hope that it will be useful,        #
#    but WITHOUT ANY WARRANTY; without even the implied warranty of         #
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          #
#    GNU General Public License for more details.                           #
#                                                                           #
#    You should have received a copy of the GNU General Public License      #
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.  #
#############################################################################

require 'net/http'
require 'libxml'
require 'base64'
require 'pp'


module IMGSrc

    class InfoError < RuntimeError; end
    class LoginError < RuntimeError; end
    class CreateError < RuntimeError; end
    class UploadError < RuntimeError; end

    Album = Struct.new( 'Album', :id, :name, :size, :date, :password, :photos )
    Photo = Struct.new( 'Photo', :id, :page, :small, :big )
    Category = Struct.new( 'Category', :name, :parent_id )

    class API
        ROOT_HOST = 'imgsrc.ru'
        PROTO_VER = '0.8'
        CACHE_DIR = '.imgsrc'

        class << self
            include LibXML

            @@http_conn  = Net::HTTP.new(ROOT_HOST)     # this method does not open the TCP connection
            @@categories = nil

            # Get photo categories hash (id=>category)
            def categories
                @@categories || load_categories
            end

            def call_get(method, params = {}, cachable = :nocache)
                uri = "/#{method}#{params.empty? ? '' : '?'}#{params.map{ |key, value| "#{key}=#{value}" }.join('&')}"

                params_string = params.map { |k, v| /passw/ =~ k ? nil : "_#{k}-#{ k == 'create' ? v.encode('UTF-8') : v }" }
                cached_file = "#{CACHE_DIR}/#{method.gsub(/\//, '-')}#{params_string.compact.join}.xml"
                if cachable == :cache && File::exists?( cached_file )
                    puts "using cached #{cached_file}"
                    return File.read( cached_file )
                else
                    # puts "fetching #{uri} to #{cached_file}"
                    result = @@http_conn.get( uri ).body
                    File.new( cached_file, "w" ).write( result ) rescue nil
                    return result
                end
            rescue Exception => x
                raise RuntimeError, "can not load #{method.sub(/.*\./, "")}: #{x.message}"
            end

            def extract_info(response)
                info = XML::Parser.string(response).parse.find_first '/info'
                raise RuntimeError, "Invalid xml:\r\n#{response}" unless info
                raise InfoError, "Unsupported protocol version #{info['proto']}" unless info['proto'] == PROTO_VER
                info
            end

        private
            # Fetch categories list 
            def load_categories
                info = extract_info(call_get('cli/cats.php', {}, :nocache))
                @@categories = {}
                info.find('categories/category').each do |node|
                    next unless id = node['id']
                    name      = node.find_first('name').content rescue nil
                    parent_id = node.find_first('parent_id').content rescue nil
                    @@categories[id] = Category.new(name, parent_id)
                end
                @@categories
            end

        end

        attr_reader :username, :albums

        def initialize(user, passwd_md5)
            @username   = user
            @Login      = { :login => @username, :passwd => passwd_md5 }
            @storage    = nil           # hostname of imgsrc storge server
            @stor_conn  = nil           # http-connection to storage host
            @albums     = []

            Dir.mkdir( CACHE_DIR ) unless File.directory?( CACHE_DIR )
        end

        # Login and fetch user info
        def login
            raise LoginError, 'already logined' if @storage
            begin
                parse_info(self.class.call_get('cli/info.php', @Login, :nocache))
            rescue InfoError => x
                raise LoginError, x.message
            end
            self
        end

        # Create new album. Optional arguments: category, passwd
        def create_album(name, args = {})
            album = get_album(name) rescue nil
            raise CreateError, "Album #{name} already exists: #{album.size} photos, modified #{album.date}" if album

            params = { :create => name.encode('CP1251') }
            params[:create_category] = args[:category] if args[:category]
            params[:create_passwd] = args[:passwd] if args[:passwd]
            parse_info(self.class.call_get('cli/info.php', @Login.merge(params)))
        end

        # Get existing album by name
        def get_album(name)
            @albums.fetch( @albums.index { |album| album.name == name } ) rescue raise RuntimeError, "no album #{name}"
        end

        # Shortcut for getting exising album or creating new one
        def get_or_create_album(name, args = {})
            album = get_album(name) rescue nil
            return album if album
            create_album(name, args)
            get_album(name)             # create_album receives full list - additional get_album() call required
        end

        # Upload files to album
        def upload(name, files)
            raise RuntimeError, 'user is not logined (no storage host)' unless @stor_conn
            album = get_album(name)
            uri = "/cli/post.php?#{@Login.map{ |k, v| "#{k}=#{v}" }.join('&')}&album_id=#{album.id}"
            photos = nil
            files.each do |file|    # imgsrc.ru badly handles multi-file uploads (unstable work, unrecoverable errors)
                puts "uploading #{file}..."
                photos, retries = nil, 3
                begin
                    photos = do_upload(uri, [file], :nobase64)
                rescue Exception => x
                    puts "#{File.basename(file)}: upload failed (#{x.message}), #{retries - 1} retries left"
                    retry if (retries -= 1) > 0
                    raise UploadError, x.message
                end
            end
            album.photos, album.size = photos, photos.size if photos    # imgsrc returns whole album in response
            pp album
        end

    private
        # Parse info.php response
        def parse_info(response)
            info = self.class.extract_info(response)
            status, error = info.find_first('status'), info.find_first('error')
            raise RuntimeError, "No status in response info:\r\n#{info}" unless status
            raise InfoError, error ? error.content : 'unknown' unless status.content == 'OK'

            raise RuntimeError, 'No storage ID in server response' unless storage = info.find_first('store')
            host = "e#{storage.content}.#{ROOT_HOST}"
            @stor_conn, @storage = Net::HTTP.new(host), host unless @storage == host

            @albums = []
            info.find('albums/album').each do |node|
                album = Album.new(node['id'])
                album.name     = node.find_first('name').content rescue nil
                album.size     = node.find_first('photos').content.to_i rescue 0
                album.date     = node.find_first('modified').content rescue nil
                album.password = node.find_first('password').content rescue nil
                album.photos   = []
                @albums << album
            end
        end

        BOUNDARY  = 'x----------------------------Rai8cheth7thi6ee'

        # Upload files to hosting
        # TODO fix base64
        def do_upload(uri, files, encoding = :binary)
            raise LoginError, 'no files' if files.empty?

            post_body = []

            files.each_index do |index|
                file = files[index]
                filename = File.basename(file)
                data = file.empty? ? '' : File.read(file)

                headers = []
                headers << "--#{BOUNDARY}\r\n"
                headers << "Content-Disposition: form-data; name=\"u#{index+1}\"; filename=\"#{filename}\"\r\n"
                headers << "Content-Type: #{data.empty? ? 'application/octet-stream' : 'image/jpeg'}\r\n"
                headers << "Content-Length: #{data.size}\r\n" unless data.empty? || encoding == :base64
                headers << "Content-Transfer-Encoding: base64\r\n" if encoding == :base64
                headers << "\r\n"

                post_body << headers.join
                post_body << (encoding == :base64 ? Base64.encode64(data) : data)
                post_body << "\r\n"
            end
            post_body << "--#{BOUNDARY}--\r\n"

            request = Net::HTTP::Post.new(uri)
            request.body = post_body.join

            # request["Connection"] = 'keep-alive'
            request["Content-Type"] = "multipart/form-data, boundary=#{BOUNDARY}"

            response = @stor_conn.request(request)
            raise UploadError, "Code #{response.code}: #{response.body}" unless response.kind_of?(Net::HTTPSuccess)
            parse_upload(self.class.extract_info(response.body))
        end

        # Parse file uploading response
        def parse_upload(info)
            status, error = info.find_first('status'), info.find_first('error')
            raise RuntimeError, "no status in upload response:\n#{info}" unless status
            raise UploadError, error ? error.content : 'unknown' unless status.content == 'OK'

            raise RuntimeError, "no uploads in\r\n#{info}" unless uploads = info.find_first('uploads')
            photos = []
            uploads.find('photo').each do |node|
                photo = Photo.new(node['id'])
                photo.page  = node.find_first('page').content rescue nil
                photo.small = node.find_first('small').content rescue nil
                photo.big   = node.find_first('big').content rescue nil
                photos << photo
            end
            photos
        end
    end
end
