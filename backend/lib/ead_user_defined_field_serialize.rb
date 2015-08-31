class EADUserDefinedFieldSerialize

  def call(data, xml, fragments, context)

    return unless context == :did

    if data.user_defined && data.user_defined['enum_1']

      xml.physloc('label' => 'Location', 'audience' => 'internal') {
        xml.text data.user_defined['enum_1'].gsub(/^.* - /, '')
      }
    end

  end
end
