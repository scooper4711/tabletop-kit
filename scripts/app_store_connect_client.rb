# frozen_string_literal: true

# The App Store Connect API client that the pipeline scripts share. Specified in docs/specs/app-store-pipeline.

require 'base64'
require 'json'
require 'net/http'
require 'openssl'
require 'uri'

class AppStoreConnectError < StandardError; end

# Signs requests to the App Store Connect API.
class AppStoreConnectClient
  BASE = 'https://api.appstoreconnect.apple.com'
  TOKEN_LIFETIME = 900

  def initialize(key_id:, issuer_id:, key_file:)
    @key_id = key_id
    @issuer_id = issuer_id
    @key = read_key(key_file)
  end

  def get(path, params = {})
    uri = URI("#{BASE}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?
    send_request(Net::HTTP::Get.new(uri), uri).fetch('data')
  end

  def post(path, body)
    send_json(Net::HTTP::Post, path, body)
  end

  def patch(path, body)
    send_json(Net::HTTP::Patch, path, body)
  end

  def delete(path)
    uri = URI("#{BASE}#{path}")
    send_request(Net::HTTP::Delete.new(uri), uri)
  end

  private

  def read_key(key_file)
    OpenSSL::PKey.read(File.read(key_file))
  rescue OpenSSL::PKey::PKeyError
    raise AppStoreConnectError, "#{key_file} isn't a readable App Store Connect key"
  end

  def send_json(request_class, path, body)
    uri = URI("#{BASE}#{path}")
    request = request_class.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(body)
    send_request(request, uri)
  end

  def send_request(request, uri)
    request['Authorization'] = "Bearer #{token}"
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    raise_unless_success(request, uri, response)
    response.body.to_s.empty? ? {} : JSON.parse(response.body)
  rescue JSON::ParserError
    raise AppStoreConnectError, "#{request.method} #{uri.path} gave a response that isn't JSON"
  end

  def raise_unless_success(request, uri, response)
    return if response.is_a?(Net::HTTPSuccess)

    raise AppStoreConnectError, "#{request.method} #{uri.path} failed: HTTP #{response.code} #{response.body}"
  end

  def token
    now = Time.now.to_i
    header = { alg: 'ES256', kid: @key_id, typ: 'JWT' }
    claims = { iss: @issuer_id, iat: now, exp: now + TOKEN_LIFETIME, aud: 'appstoreconnect-v1' }
    signed = [header, claims].map { |part| encode(JSON.generate(part)) }.join('.')
    "#{signed}.#{encode(raw_signature(signed))}"
  end

  # OpenSSL gives a DER signature; a JWT wants the two 32-byte numbers side by side.
  def raw_signature(data)
    numbers = OpenSSL::ASN1.decode(@key.sign(OpenSSL::Digest.new('SHA256'), data)).value
    numbers.map { |number| number.value.to_s(2).rjust(32, "\0") }.join
  end

  def encode(bytes)
    Base64.urlsafe_encode64(bytes, padding: false)
  end
end
