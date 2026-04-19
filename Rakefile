desc "Start HTTP development server"
task :server do
  sh "ruby -run -e httpd . -p 8001"
end

desc "Start HTTPS development server (required for Web MIDI on Android Chrome)"
task :https do
  require 'webrick'
  require 'webrick/https'
  require 'openssl'

  cert_dir  = File.expand_path('.certs', __dir__)
  cert_path = File.join(cert_dir, 'server.crt')
  key_path  = File.join(cert_dir, 'server.key')
  port      = ENV['PORT']&.to_i || 8443
  doc_root  = __dir__

  # Generate self-signed cert on first run
  unless File.exist?(cert_path) && File.exist?(key_path)
    FileUtils.mkdir_p(cert_dir)
    puts "[https] Generating self-signed certificate in #{cert_dir}/ ..."

    key  = OpenSSL::PKey::RSA.new(2048)
    name = OpenSSL::X509::Name.parse('/CN=naumanica.local')
    cert = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = Time.now.to_i
    cert.subject    = name
    cert.issuer     = name
    cert.public_key = key.public_key
    cert.not_before = Time.now
    cert.not_after  = Time.now + (365 * 24 * 60 * 60 * 5)  # 5 years

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate  = cert
    cert.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.add_extension(ef.create_extension('subjectKeyIdentifier', 'hash', false))
    cert.add_extension(ef.create_extension(
      'subjectAltName',
      'DNS:naumanica.local,DNS:localhost,IP:127.0.0.1',
      false
    ))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    File.write(cert_path, cert.to_pem)
    File.write(key_path,  key.to_pem)
    File.chmod(0600, key_path)
    puts "[https] Certificate generated."
  end

  server = WEBrick::HTTPServer.new(
    Port:            port,
    BindAddress:     '0.0.0.0',
    DocumentRoot:    doc_root,
    SSLEnable:       true,
    SSLCertificate:  OpenSSL::X509::Certificate.new(File.read(cert_path)),
    SSLPrivateKey:   OpenSSL::PKey::RSA.new(File.read(key_path)),
    SSLCertName:     [['CN', 'naumanica.local']]
  )

  trap('INT') { server.shutdown }
  puts "[https] Serving #{doc_root} at https://naumanica.local:#{port}/"
  puts "[https] On Android Chrome: accept the cert warning (Advanced → Proceed)."
  server.start
end

task default: :server
