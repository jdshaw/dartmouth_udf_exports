require_relative 'lib/aspace_patches'
require_relative 'lib/ead_user_defined_field_serialize'
require_relative 'lib/marc_user_defined_field_serialize'

# Register our custom serialize steps.
EADSerializer.add_serialize_step(EADUserDefinedFieldSerialize)
MARCSerializer.add_decorator(MARCUserDefinedFieldSerialize)


require 'i18n'

if !I18n.respond_to?(:t_raw)
  Log.info("Loading temporary I18n backend fixes (to be merged with https://github.com/archivesspace/archivesspace/pull/316)")

  I18n.enforce_available_locales = false # do not require locale to be in available_locales for export
  I18n.load_path += ASUtils.find_locales_directories(File.join("enums", "#{AppConfig[:locale]}.yml"))

  # Allow overriding of the i18n locales via the 'local' folder(s)
  ASUtils.wrap(ASUtils.find_local_directories).map{|local_dir| File.join(local_dir, 'frontend', 'locales')}.reject { |dir| !Dir.exists?(dir) }.each do |locales_override_directory|
    I18n.load_path += Dir[File.join(locales_override_directory, '**' , '*.{rb,yml}')]
  end

  module I18n

    def self.t(*args)
      self.t_raw(*args)
    end

    def self.t_raw(*args)
      key = args[0]
      default = if args[1].is_a?(String)
                  args[1]
                else
                  (args[1] || {}).fetch(:default, "")
                end

      # String
      if key && key.kind_of?(String) && key.end_with?(".")
        return default
      end

      # Hash / Enumeration Value
      if key && key.kind_of?(Hash) && key.has_key?(:enumeration)
        backend  = config.backend
        locale   = config.locale

        # Null character to cope with enumeration values containing dots.  Eugh.
        translation = backend.send(:lookup, locale, ['enumerations', key[:enumeration], key[:value]].join("\0"), [], {:separator => "\0"}) || default

        if translation && !translation.empty?
          return translation
        end
      end


      self.translate(*args)
    end

  end
end
