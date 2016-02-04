# All the horror in one convenient location!  We'll send pull requests for the
# changes we've made to core (which are relatively small, despite all the copy
# pasta you see here).  For now, we override the bits we need to override.

# the fix for returning a '|||' for a missing language has been incorporated
# upstream now, so this class only contains the Dartmouth-specific modifications
# made by @jdshaw -- Mark Triggs, Friday 16 October, 2015
#
class MARCModel < ASpaceExport::ExportModel
  attr_reader :aspace_record

  def initialize(obj)
     @datafields = {}
     @aspace_record = obj
  end

  def controlfields
    []
  end

  def self.from_aspace_object(obj)
    self.new(obj)
  end
  
  # change the record type to "t" rather than "p" in the leader
  def self.from_resource(obj)
    marc = self.from_archival_object(obj)
    marc.apply_map(obj, @resource_map)
    marc.leader_string = "00000nt$ a2200000 u 4500"
    marc.leader_string[7] = obj.level == 'item' ? 'm' : 'c'

    marc.controlfield_string = assemble_controlfield_string(obj)

    marc
  end
     
  def handle_language(langcode)
    # don't export the 040, 041 and 049 language codes - local rules
  end
  
  # https://github.com/archivesspace/archivesspace/pull/252
  def self.assemble_controlfield_string(obj)
    date = obj.dates[0] || {}
    string = obj['system_mtime'].scan(/\d{2}/)[1..3].join('')
    string += obj.level == 'item' && date['date_type'] == 'single' ? 's' : 'i'
    string += date['begin'] ? date['begin'][0..3] : "    "
    string += date['end'] ? date['end'][0..3] : "    "
    string += "xx"
    18.times { string += ' ' }
    string += (obj.language || '|||')
    string += ' d'

    string
  end
  
  # override to use Dates of Existence rather than the dates in the name form for creators
  def handle_primary_creator(linked_agents)
    link = linked_agents.find{|a| a['role'] == 'creator'}
    return nil unless link

    creator = link['_resolved']
    name = creator['display_name']
    dates_of_existence = creator['dates_of_existence'][0] ? creator['dates_of_existence'][0] : ''
    agent_dates = ''
    ind2 = ' '
    role_info = link['relator'] ? ['4', link['relator']] : ['e', 'creator']
    
    # dates of existence
    if dates_of_existence['begin']
      agent_dates = dates_of_existence['begin']
      if dates_of_existence['end']
        agent_dates = agent_dates + "-" + dates_of_existence['end']
      end
    else if dates_of_existence['expression']
      agent_dates = dates_of_existence['expression']
    end
    end
    
    if agent_dates.empty?
        agent_dates = name['dates']
    end

    case creator['agent_type']

    when 'agent_corporate_entity'
      code = '110'
      ind1 = '2'
      sfs = [
              ['a', name['primary_name']],
              ['b', name['subordinate_name_1']],
              ['b', name['subordinate_name_2']],
              ['n', name['number']],
              ['d', agent_dates],
              ['g', name['qualifier']],
            ]

    when 'agent_person'
      joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
      name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)

      code = '100'
      sfs = [
              ['a', name_parts],
              ['b', name['number']],
              ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
              ['q', name['fuller_form']],
              ['d', agent_dates],
              ['g', name['qualifier']],
            ]

    when 'agent_family'
      code = '100'
      ind1 = '3'
      sfs = [
              ['a', name['family_name']],
              ['c', name['prefix']],
              ['d', agent_dates],
              ['g', name['qualifier']],
            ]
    end

    sfs << role_info
    df(code, ind1, ind2).with_sfs(*sfs)
  end
  
  # switch the order of the extents for local rules
  def handle_extents(extents)
    extents.each do |ext|
      
      extent = ''
      
      e2 = ext['number']
      e2 << " #{I18n.t('enumerations.extent_extent_type.'+ext['extent_type'], :default => ext['extent_type'])}"

      if ext['container_summary']
        extent = ext['container_summary']
        extent << " (#{e2})"
      else
        extent = e2
      end

      df!('300').with_sfs(['a', extent])
    end
  end
  
  # override to change finding aid 856 language
  def handle_ead_loc(ead_loc)
    df('555', ' ', ' ').with_sfs(
                                  ['a', "View the finding aid for this resource."],
                                  ['u', ead_loc]
                                )
    df('856', '4', '2').with_sfs(
                                  ['z', "View the finding aid for this resource."],
                                  ['u', ead_loc]
                                )
  end
  
end


if !EADSerializer.respond_to?(:add_serialize_step)

  class EADSerializer < ASpaceExport::Serializer

    # Allow plugins to hook in to record processing by providing their own
    # serialization step (a class with a 'call' method accepting the arguments
    # defined in `run_serialize_step`.
    def self.add_serialize_step(serialize_step)
      @extra_serialize_steps ||= []
      @extra_serialize_steps << serialize_step
    end

    def self.run_serialize_step(data, xml, fragments, context)
      Array(@extra_serialize_steps).each do |step|
        step.new.call(data, xml, fragments, context)
      end
    end


    def stream(data)
      @stream_handler = ASpaceExport::StreamHandler.new
      @fragments = ASpaceExport::RawXMLHandler.new
      @include_unpublished = data.include_unpublished?
      @use_numbered_c_tags = data.use_numbered_c_tags?
      @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

      doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
        begin 

          xml.ead(                  'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                                    'xsi:schemaLocation' => 'urn:isbn:1-931666-22-9 http://www.loc.gov/ead/ead.xsd',
                                    'xmlns:xlink' => 'http://www.w3.org/1999/xlink') {

            xml.text (
              @stream_handler.buffer { |xml, new_fragments|
                serialize_eadheader(data, xml, new_fragments)
              })

            atts = {:level => data.level, :otherlevel => data.other_level}

            if data.publish === false
              if @include_unpublished
                atts[:audience] = 'internal'
              else
                return
              end
            end

            atts.reject! {|k, v| v.nil?}

            xml.archdesc(atts) {
              


              xml.did {
                

                if (val = data.language)
                  xml.langmaterial {
                    xml.language(:langcode => val) {
                      xml.text I18n.t("enumerations.language_iso639_2.#{val}", :default => val)
                    }
                  }
                end

                if (val = data.repo.name)
                  xml.repository {
                    xml.corpname { sanitize_mixed_content(val, xml, @fragments) }
                  }
                end

                if (val = data.title)
                  xml.unittitle  {   sanitize_mixed_content(val, xml, @fragments) } 
                end

                serialize_origination(data, xml, @fragments)

                xml.unitid (0..3).map{|i| data.send("id_#{i}")}.compact.join('.')

                serialize_extents(data, xml, @fragments)

                serialize_dates(data, xml, @fragments)

                serialize_did_notes(data, xml, @fragments)

                data.instances_with_containers.each do |instance|
                  serialize_container(instance, xml, @fragments)
                end

                EADSerializer.run_serialize_step(data, xml, @fragments, :did)

              }# </did>
              
              data.digital_objects.each do |dob|
                serialize_digital_object(dob, xml, @fragments)
              end

              serialize_nondid_notes(data, xml, @fragments)

              serialize_bibliographies(data, xml, @fragments)

              serialize_indexes(data, xml, @fragments)

              serialize_controlaccess(data, xml, @fragments)

              EADSerializer.run_serialize_step(data, xml, @fragments, :archdesc)

              xml.dsc {

                data.children_indexes.each do |i|
                  xml.text(
                    @stream_handler.buffer {|xml, new_fragments|
                      serialize_child(data.get_child(i), xml, new_fragments)
                    }
                  )
                end
              }
            }
          }
          
        rescue => e
          xml.text  "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF YOUR RESOURCE. THE FOLLOWING INFORMATION MAY HELP:\n
                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
        end
        
        
        
      end
      doc.doc.root.add_namespace nil, 'urn:isbn:1-931666-22-9'

      Enumerator.new do |y|
        @stream_handler.stream_out(doc, @fragments, y)
      end
      
      
    end


    def serialize_child(data, xml, fragments, c_depth = 1)
      begin 
        return if data["publish"] === false && !@include_unpublished

        tag_name = @use_numbered_c_tags ? :"c#{c_depth.to_s.rjust(2, '0')}" : :c

        atts = {:level => data.level, :otherlevel => data.other_level, :id => prefix_id(data.ref_id)}

        if data.publish === false
          atts[:audience] = 'internal'
        end

        atts.reject! {|k, v| v.nil?}
        xml.send(tag_name, atts) {

          xml.did {
            if (val = data.title)
              xml.unittitle {  sanitize_mixed_content( val,xml, fragments) } 
            end

            if !data.component_id.nil? && !data.component_id.empty?
              xml.unitid data.component_id
            end

            serialize_origination(data, xml, fragments)
            serialize_extents(data, xml, fragments)
            serialize_dates(data, xml, fragments)
            serialize_did_notes(data, xml, fragments)

            EADSerializer.run_serialize_step(data, xml, fragments, :did)

            # TODO: Clean this up more; there's probably a better way to do this.
            # For whatever reason, the old ead_containers method was not working
            # on archival_objects (see migrations/models/ead.rb).

            data.instances.each do |inst|
              case 
              when inst.has_key?('container') && !inst['container'].nil?
                serialize_container(inst, xml, fragments)
              when inst.has_key?('digital_object') && !inst['digital_object']['_resolved'].nil?
                serialize_digital_object(inst['digital_object']['_resolved'], xml, fragments)
              end
            end

          }

          serialize_nondid_notes(data, xml, fragments)

          serialize_bibliographies(data, xml, fragments)

          serialize_indexes(data, xml, fragments)

          serialize_controlaccess(data, xml, fragments)

          EADSerializer.run_serialize_step(data, xml, fragments, :archdesc)

          data.children_indexes.each do |i|
            xml.text(
              @stream_handler.buffer {|xml, new_fragments|
                serialize_child(data.get_child(i), xml, new_fragments, c_depth + 1)
              }
            )
          end
        }
      rescue => e
        xml.text "ASPACE EXPORT ERROR : YOU HAVE A PROBLEM WITH YOUR EXPORT OF ARCHIVAL OBJECTS. THE FOLLOWING INFORMATION MAY HELP:\n

                MESSAGE: #{e.message.inspect}  \n
                TRACE: #{e.backtrace.inspect} \n "
      end
    end



  end
end


if !MARCSerializer.respond_to?(:add_decorator)

  class MARCSerializer < ASpaceExport::Serializer

    # Allow plugins to wrap the MARC record with their own behavior.  Gives them
    # the chance to change the leader, 008, add extra data fields, etc.
    def self.add_decorator(decorator)
      @decorators ||= []
      @decorators << decorator
    end

    def self.decorate_record(record)
      Array(@decorators).reduce(record) {|result, decorator|
        decorator.new(result)
      }
    end

    def serialize(marc, opts = {})

      builder = build(marc, opts)
      builder = build(MARCSerializer.decorate_record(marc), opts)

      builder.to_xml
    end


    def _root(marc, xml)

      xml.collection('xmlns' => 'http://www.loc.gov/MARC21/slim',
                     'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                     'xsi:schemaLocation' => 'http://www.loc.gov/standards/marcxml/schema/MARC21slim.xsd'){

        xml.record {

          xml.leader {
            xml.text marc.leader_string
          }

          xml.controlfield(:tag => '008') {
            xml.text marc.controlfield_string
          }

          marc.controlfields.each do |cf|
            xml.controlfield(:tag => cf.tag) {
              xml.text cf.text
            }
          end

          marc.datafields.each do |df|

            df.ind1 = ' ' if df.ind1.nil?
            df.ind2 = ' ' if df.ind2.nil?

            xml.datafield(:tag => df.tag, :ind1 => df.ind1, :ind2 => df.ind2) {

              df.subfields.each do |sf|

                xml.subfield(:code => sf.code){
                  xml.text sf.text.gsub(/<[^>]*>/, ' ')
                }
              end
            }
          end
        }
      }
    end
  end

end
