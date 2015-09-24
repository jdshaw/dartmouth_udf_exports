class EADUserDefinedFieldSerialize

  def call(data, xml, fragments, context)

    if context == :did
      if data.user_defined && data.user_defined['enum_1']

        xml.physloc('label' => 'Location', 'audience' => 'internal') {
          xml.text data.user_defined['enum_1'].gsub(/^.* - /, '')
        }
      end
    elsif context == :archdesc
      # FIXME: Contribute this to the core code?
      ASUtils.wrap(data.linked_agents).each do |linked_agent|
        agent = linked_agent['_resolved']

        if linked_agent['role'] == 'creator'
          xml.bioghist {
            xml.head {
              if agent['jsonmodel_type'] == 'agent_corporate_entity'
                xml.text("Introduction")
              else
                xml.text("Biography")
              end
            }
            agent['notes'].each do |note|
              if note['jsonmodel_type'] == 'note_bioghist'
                ASUtils.wrap(note['subnotes']).each do |subnote|
                  if subnote['jsonmodel_type'] == 'note_text'
                    xml.p {
                      xml.text(subnote['content'])
                    }
                  end
                end
              end
            end
          }
        end
      end
    end

  end
end
