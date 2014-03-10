require File.expand_path('lib/imgsrc', File.dirname(__FILE__))

spec = Gem::Specification.new do |s|
    s.name = 'imgsrc'
    s.version = "#{IMGSrc::API::PROTO_VER}.4"
    s.summary = 'iMGSRC photo-hosting client.'
    s.description = 'Simple client for imgsrc.ru photo-hosting' # TODO : library, console-client, gui-client.'
    s.author = 'Vasiliy Yeremeyev'
    s.email = 'vayerx@gmail.com'
    s.homepage = 'http://github.com/vayerx/imgsrc'
    s.license = 'GPL-3'
    s.has_rdoc = false

    s.required_ruby_version = '~> 1.9.2'
    # TODO s.requirements << 'libglade, v2.6 or higher (used only by imgsrc-gui)'
    s.add_dependency( 'libxml-ruby', '>= 2.2.2' )
    s.add_dependency( 'parseconfig', '>= 1.0.4' )
    s.add_dependency( 'optiflag',    '>= 0.7' )

    s.bindir = 'bin'
    s.executables = [
        'imgsrc'
        # TODO 'imgsrc-gui'
    ]
    s.files = [
        'lib/imgsrc.rb'
        # TODO 'ui/imgsrc.glade'
    ]
end
