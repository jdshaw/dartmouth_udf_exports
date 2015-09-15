class MARCUserDefinedFieldSerialize

  ControlField = Struct.new(:tag, :text)
  DataField = Struct.new(:tag, :ind1, :ind2, :subfields)
  SubField = Struct.new(:code, :text)

  AUDIO_007 = 'ss lunjlca   e'.ljust(26)

  def initialize(record)
    @record = record
  end


  def leader_string
    result = @record.leader_string

    # result
    $stderr.puts("\n*** DEBUG #{(Time.now.to_f * 1000).to_i} [marc_user_defined_field_serialize.rb:12 9aa35f]: " + {'result' => result}.inspect + "\n")

    result
  end


  def controlfields
    extra_fields = []

    if @record.aspace_record.user_defined && @record.aspace_record.user_defined['boolean_1']
      # An audio recording.  Emit an extra 007 control field.
      extra_fields = [ControlField.new('007', AUDIO_007)]
    end

    (@record.controlfields + extra_fields).sort_by(&:tag)
  end


  def datafields
    extra_fields = []
    if @record.aspace_record.user_defined

      user_defined = @record.aspace_record.user_defined


      if user_defined['enum_1']
        location_code = user_defined['enum_1'].gsub(/^.* - /, '')
        extra_fields << DataField.new('950', '0', '4', [SubField.new('l', location_code)])
      end

      if user_defined['text_1']
        extra_fields << DataField.new('580', ' ', ' ', [SubField.new('a', user_defined['text_1'])])
        extra_fields << DataField.new('830', ' ', '0', [SubField.new('p', user_defined['text_1'].sub("Forms part of: ", ""))])
      end
    end

    (@record.datafields + extra_fields).sort_by(&:tag)
  end


  def method_missing(*args)
    @record.send(*args)
  end

end
