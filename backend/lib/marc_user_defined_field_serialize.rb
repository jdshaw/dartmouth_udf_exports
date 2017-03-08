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
    
    if @record.aspace_record.ead_id
      extra_fields << DataField.new('035', ' ', ' ', [SubField.new('a', @record.aspace_record.ead_id)])
    end
    
    if @record.aspace_record.id_0
      prefer_cite = "Rauner " + @record.aspace_record.id_0 + "; Rauner Special Collections Library, Dartmouth College, Hanover, NH."
      extra_fields << DataField.new('524', ' ', ' ', [SubField.new('a', prefer_cite)])
    end
    
    
    if @record.aspace_record.user_defined

      user_defined = @record.aspace_record.user_defined

      if user_defined['enum_1'] && @record.aspace_record.id_0
        location_code = user_defined['enum_1'].gsub(/^.* - /, '')
        extra_fields << DataField.new('950', '0', '4', [SubField.new('b', @record.aspace_record.id_0),SubField.new('l', location_code)])
      end

      if user_defined['text_1']
        extra_fields << DataField.new('580', ' ', ' ', [SubField.new('a', user_defined['text_1'])])
        extra_fields << DataField.new('710', '2', ' ', [SubField.new('a', user_defined['text_1'])])
      end

      if user_defined['text_1'] && user_defined['text_2']
        extra_fields << DataField.new('830', ' ', '0', [SubField.new('a', user_defined['text_1']), SubField.new('p', user_defined['text_2'])])
      end
      
      if user_defined['text_5']
        extra_fields << DataField.new('518', ' ', ' ', [SubField.new('a', user_defined['text_5'])])
      end

    end

    (@record.datafields + extra_fields).sort_by(&:tag)
  end


  def method_missing(*args)
    @record.send(*args)
  end

end
