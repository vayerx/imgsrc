spec = Gem::Specification.new do |s|
    s.name = 'imgsrc'
    s.summary = 'iMGSRC client.'
    s.version = '0.8'
    s.description = 'Simple client for imgsrc.ru photo-hosting'
    s.author = 'Vasiliy Yeremeyev'
    s.email = 'vayerx@gmail.com'
    s.homepage = 'http://github.com/vayerx/imgsrc'
    s.has_rdoc = false
    s.bindir = 'bin'
    s.executables << 'imgsrc' # << 'imgsrc-gui'
    s.add_dependency( 'libxml-ruby', '>= 2.2.2' )
    s.add_dependency( 'parseconfig', '>= 0.5.2' )
    s.files = [
        'lib/imgsrc.rb',
        'ui/imgsrc.glade'
    ]
end
