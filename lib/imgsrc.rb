#!/usr/bin/env ruby

require 'net/http'
require 'libxml'
require 'base64'
require 'pp'
#require 'progressbar'


module IMGSrc

    class InfoError < RuntimeError; end
    class LoginError < RuntimeError; end
    class CreateError < RuntimeError; end
    class UploadError < RuntimeError; end

    Album = Struct.new( 'Album', :id, :name, :size, :date, :password, :photos )
    Photo = Struct.new( 'Photo', :id, :page, :small, :big )

    class API
        include LibXML

        ROOT_HOST = 'imgsrc.ru'
        PROTO_VER = '0.8'
        CACHE_DIR = '.imgsrc'

        attr_reader :username, :albums, :http_conn

        def initialize( user, passwd_md5 )
            @username   = user
            @Login      = { :login => @username, :passwd => passwd_md5 }
            @http_conn  = Net::HTTP.new( ROOT_HOST )    # this method does not open the TCP connection
            @storage    = nil                           # hostname of imgsrc storge server
            @stor_conn  = nil                           # http-connection to storage host
            @albums     = []

            Dir.mkdir( CACHE_DIR ) unless File.directory?( CACHE_DIR )
        end

        # Login and fetch user/categories info
        def login
            raise LoginError, 'already logined' if @storage
            begin
                parse_info( call_get( 'cli/info.php', @Login, :nocache ) )
            rescue InfoError => x
                raise LoginError, x.message
            end
            self
        end

        # Create new album. Optional arguments: category, passwd
        def create_album( name, args = {} )
            album = get_album( name ) rescue nil
            raise CreateError, "Album #{name} already exists: #{album.size} photos, modified #{album.date}" if album

            params = { :create => name.encode( 'CP1251' ) }
            params[:create_category] = args[:category] if args[:category]
            params[:create_passwd] = args[:passwd] if args[:passwd]
            parse_info( call_get( 'cli/info.php', @Login.merge( params ), :nocache ) )
        end

        # Get existing album by name
        def get_album( name )
            @albums.fetch( @albums.index { |album| album.name == name } ) rescue raise RuntimeError, "no album #{name}"
        end

        def get_or_create_album( name )
            album = get_album( name ) rescue nil
            return album if album
            create_album( name )    # create_album receives full list
            get_album( name )
        end

        # Upload files to album
        def upload(name, files)
            raise RuntimeError, 'user is not logined (no storage host)' unless @stor_conn
            album = get_album( name )
            uri = "/cli/post.php?#{@Login.map{ |k, v| "#{k}=#{v}" }.join('&')}&album_id=#{album.id}"
            photos = do_upload( uri, files ) #, :nobase64 )
            album.photos += photos      # album.photos doesn't contain photos uploaded in the past
            album.size += photos.size
            pp album
        end

    private
        # Parse info.php response
        def parse_info( response )
            info = XML::Parser.string( response ).parse.find_first '/info'
            raise RuntimeError, "Invalid xml:\r\n#{response}" unless info
            raise InfoError, "Unsupported protocol version #{info['proto']}" unless info['proto'] == PROTO_VER

            status, error = info.find_first( 'status' ), info.find_first( 'error' )
            raise RuntimeError, "No status in response info:\r\n#{info}" unless status
            raise InfoError, error ? error.content : 'unknown' unless status.content == 'OK'

            raise RuntimeError, 'No storage ID in server response' unless storage = info.find_first( 'store' )
            host = "e#{storage.content}.#{ROOT_HOST}"
            @stor_conn, @storage = Net::HTTP.new( host ), host unless @storage == host

            @albums = []
            info.find( 'albums/album' ).each do |node|
                album = Album.new( node['id'] )
                album.name = node.find_first('name').content rescue nil
                album.size = node.find_first('photos').content.to_i rescue 0
                album.date = node.find_first('modified').content rescue nil
                album.password = node.find_first('password').content rescue nil
                album.photos = []
                @albums << album
            end
        end

        # Call http-method with optional caching (mostly, for debug-only purpose)
        def call_get( method, params_hash, cachable )
            params = params_hash.map{ |k, v| "#{k}=#{v}" }.join('&')
            uri = "/#{method}?#{params}"

            #params_string = params_hash.map{ |k, v| /passw/ =~ k.to_s ? nil : "_#{k}-#{v}" }.compact.join
            #cached_file = "#{CACHE_DIR}/#{method.gsub(/\//, '-')}#{params_string}.xml"
            #if cachable == :cache && File::exists?( cached_file )
            #    puts "using cached #{cached_file}"
            #    return File.read( cached_file )
            #else
            #    puts "fetching #{uri} to #{cached_file}"
                result = @http_conn.get( uri ).body
            #    File.new( cached_file, "w" ).write( result ) rescue nil
            #    return result
            #end
        rescue
            raise RuntimeError, "can not load #{method.sub(/.*\./, "")}"
        end

        BOUNDARY  = 'x----------------------------Rai8cheth7thi6ee'

        # TODO fix base64
        def do_upload( uri, files, encoding = :binary)
            raise LoginError, 'no files' if files.empty?

            post_body = []

            files.each_index do |index|
                file = files[index]
                data = file.empty? ? '' : File.read(file)

                headers = []
                headers << "--#{BOUNDARY}\r\n"
                headers << "Content-Disposition: form-data; name=\"u#{index+1}\"; filename=\"#{File.basename(file)}\"\r\n"
                headers << "Content-Type: #{data.empty? ? 'application/octet-stream' : 'image/jpeg'}\r\n"
                headers << "Content-Length: #{data.size}\r\n" unless data.empty? || encoding == :base64
                headers << "Content-Transfer-Encoding: base64\r\n" if encoding == :base64
                headers << "\r\n"

                post_body << headers.join
                post_body << ( encoding == :base64 ? Base64.encode64(data) : data )
                post_body << "\r\n"
            end
            post_body << "--#{BOUNDARY}--\r\n"

            request = Net::HTTP::Post.new( uri )
            request.body = post_body.join

            # request["Connection"] = 'keep-alive'
            request["Content-Type"] = "multipart/form-data, boundary=#{BOUNDARY}"

            response = @stor_conn.request(request)
            raise UploadError, "Http code #{response.code}: #{response.body}" unless response.kind_of?( Net::HTTPSuccess )
            parse_upload(response.body)
        end

        def parse_upload(response)
            info = XML::Parser.string( response ).parse.find_first '/info'
            raise RuntimeError, "Invalid xml:\r\n#{response}" unless info

            status, error = info.find_first( 'status' ), info.find_first( 'error' )
            raise RuntimeError, "no status in upload response:\n#{info}" unless status
            raise UploadError, error ? error.content : 'unknown' unless status.content == 'OK'

            raise RuntimeError, "no uploads in\r\n#{info}" unless uploads = info.find_first( 'uploads' )
            photos = []
            uploads.find( 'photo' ).each do |node|
                photo = Photo.new( node['id'] )
                photo.page = node.find_first('page').content rescue nil
                photo.small = node.find_first('small').content rescue nil
                photo.big = node.find_first('big').content rescue nil
                photos << photo
            end
            photos
        end
    end

end
