# frozen_string_literal: true

require "openssl"
require "zlib"
require "active_support/core_ext/numeric"

module ActiveRecord
  module Encryption
    # An encryptor exposes the encryption API that ActiveRecord::Encryption::EncryptedAttributeType
    # uses for encrypting and decrypting attribute values.
    #
    # It interacts with a KeyProvider for getting the keys, and delegate to
    # ActiveRecord::Encryption::Cipher the actual encryption algorithm.
    #
    # It works the same way as ActiveRecord::Encryption::Encryptor, but without ever compressing the data. It still
    # handles previously compressed data.
    class EncryptorWithoutCompression < Encryptor
      def compress_if_worth_it(string)
        [string, false]
      end
    end
  end
end
