class EADUserDefinedFieldSerialize

  def call(data, xml, fragments, context)

    if context == :did
      if data.user_defined && data.user_defined['enum_1']
        enum_value = data.user_defined['enum_1']

        xml.physloc('label' => 'Location', 'audience' => 'internal') {
          xml.text I18n.t({:enumeration => 'user_defined_enum_1', :value => enum_value}, :default => enum_value).gsub(/^.* - /, '')
        }
         xml.physloc('label' => 'Location', 'audience' => 'external') {
          xml.text I18n.t({:enumeration => 'user_defined_enum_1', :value => enum_value}, :default => enum_value).gsub(/ - .*/, '')
        }
      end
      
    elsif context == :archdesc
      # FIXME: Contribute this to the core code?
      ASUtils.wrap(data.linked_agents).each do |linked_agent|
        agent = linked_agent['_resolved']

        if linked_agent['role'] == 'creator'
            agent['notes'].each do |note|
              if note['jsonmodel_type'] == 'note_bioghist'
                ASUtils.wrap(note['subnotes']).each do |subnote|
                  if subnote['jsonmodel_type'] == 'note_text'
                    if !subnote['content'].empty?
                        xml.bioghist {
                          xml.head {
                            if agent['jsonmodel_type'] == 'agent_corporate_entity'
                              xml.text("Introduction")
                            else
                              xml.text("Biography")
                            end
                          }
                          xml.p {
                            xml.text(subnote['content'])
                          }
                        }
                    end
                  end
                end
              end
            end
        end
      end
      
    elsif context == :titlestmt
      if data.user_defined && data.user_defined['text_4']
        subtitle = data.user_defined['text_4']
        xml.subtitle{xml.text(subtitle)}
      end
    end

  end
end
