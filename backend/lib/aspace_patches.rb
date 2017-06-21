# All the horror in one convenient location!  We'll send pull requests for the
# changes we've made to core (which are relatively small, despite all the copy
# pasta you see here).  For now, we override the bits we need to override.

# the fix for returning a '|||' for a missing language has been incorporated
# upstream now, so this class only contains the Dartmouth-specific modifications
# made by @jdshaw -- Mark Triggs, Friday 16 October, 2015
#
class MARCModel < ASpaceExport::ExportModel
  
  @archival_object_map = {
    :repository => :handle_repo_code,
    :title => :handle_title,
    :user_defined => :handle_title_extras,
    :linked_agents => :handle_agents,
    :subjects => :handle_subjects,
    :extents => :handle_extents,
    :language => :handle_language,
    [:dates, :id_0] => :handle_dates,
  }
  
  @resource_map = {
    [:id_0, :id_1, :id_2, :id_3] => :handle_id,
    :notes => :handle_notes,
    :finding_aid_description_rules => :handle_finding_aid_rules,
    :ead_location => :handle_ead_loc
}
  
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
  # or "k" for dcrmg
  # also change position 8 to "a" if not dcrmg
  # also change position 33 to "k" if dcrmg
  def self.from_resource(obj)
    marc = self.from_archival_object(obj)
    marc.apply_map(obj, @resource_map)
    marc.leader_string = "00000n$$$a2200000 u 4500         $"
    
    # determine cataloging standard
    marc.leader_string[6] = case obj.finding_aid_description_rules
      when 'dcrmg'
        'k'
      else 't'
    end
    
    marc.leader_string[7] = obj.level == 'item' ? 'm' : 'c'
    marc.leader_string[7] = obj.id_0 =~ /doh/i ? 'm' : marc.leader_string[7]
    
    marc.leader_string[8] = case obj.finding_aid_description_rules
      when 'dcrmg'
        ' '
      else 'a'
    end
    
    marc.leader_string[33] = case obj.finding_aid_description_rules
      when 'dcrmg'
        'k'
      else ' '
    end
    
    marc.controlfield_string = assemble_controlfield_string(obj)

    marc
  end
   
  def handle_language(langcode)
    # don't export the 040, 041 and 049 language codes - local rules
  end
  
  def handle_id(*ids)
    # don't export the 099 or 852 - local rules
  end
  
  def handle_dates(dates, id_0)
    return false if dates.empty?

    dates = [["single", "inclusive", "range"], ["bulk"]].map {|types|
      dates.find {|date| types.include? date['date_type'] }
    }.compact

    dates.each do |date|
      code = date['date_type'] == 'bulk' ? 'g' : 'f'
      val = nil
      if date['expression'] && date['date_type'] != 'bulk'
        val = date['expression']
      elsif date['date_type'] == 'single'
        val = date['begin']
        if id_0 =~/doh/i
          val = Date.parse(date['begin']).strftime('%Y %B %-d')
        end 
      else
        if id_0 =~/doh/i
          val = "#{Date.parse(date['begin']).strftime('%Y %B %-d')} - #{Date.parse(date['end']).strftime('%Y %B %-d')}"
        else
          val = "#{date['begin']} - #{date['end']}"
        end
      end

      df('245', '1', '0').with_sfs([code, val])
    end
  end
  
  def handle_finding_aid_rules(finding_aid_description_rules)
    sfs = [['e',finding_aid_description_rules]]
    
    case finding_aid_description_rules
      when 'dcrmmss'
        sfs_add = ['e','rda']
      when 'dcrmg'
        sfs_add = ['e','rda']        
    end
    if sfs_add
        sfs.unshift(sfs_add)
    end
    
    df('040', ' ', ' ').with_sfs(*sfs)

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
  
  def handle_agents(linked_agents)
    
    subjects = linked_agents.select{|a| a['role'] == 'subject'}

    subjects.each_with_index do |link, i|
      subject = link['_resolved']
      name = subject['display_name']
      relator = link['relator']
      terms = link['terms']
      ind2 = source_to_code(name['source'])

      case subject['agent_type']

      when 'agent_corporate_entity'
        code = '610'
        ind1 = '2'
        sfs = [
                ['a', name['primary_name']],
                ['b', name['subordinate_name_1']],
                ['b', name['subordinate_name_2']],
                ['n', name['number']],
                ['g', name['qualifier']],
              ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = '600'
        sfs = [
                ['a', name_parts],
                ['b', name['number']],
                ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                ['q', name['fuller_form']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      when 'agent_family'
        code = '600'
        ind1 = '3'
        sfs = [
                ['a', name['family_name']],
                ['c', name['prefix']],
                ['d', name['dates']],
                ['g', name['qualifier']],
              ]

      end

      terms.each do |t|
        tag = case t['term_type']
          when 'uniform_title'; 't'
          when 'genre_form', 'style_period'; 'v'
          when 'topical', 'cultural_context'; 'x'
          when 'temporal'; 'y'
          when 'geographic'; 'z'
          end
        sfs << [(tag), t['term']]
      end

      if ind2 == '7'
        sfs << ['2', subject['source']]
      end

      df(code, ind1, ind2, i).with_sfs(*sfs)
    end

    handle_primary_creator(linked_agents)
    
    # don't use 700 or 710 for sources, use 561 instead
    creators = linked_agents.select{|a| a['role'] == 'creator'}[1..-1] || []
    creators = creators + linked_agents.select{|a| a['role'] == 'source'}

    creators.each do |link|
      creator = link['_resolved']
      name = creator['display_name']
      relator = link['relator']
      terms = link['terms']
      role = link['role']

      if relator
        relator_sf = ['4', relator]
      elsif role == 'source'
        relator_sf =  []
      else
        relator_sf = ['e', 'creator']
      end

      ind2 = ' '
      
      if role == 'creator'
      
        case creator['agent_type']
  
        when 'agent_corporate_entity'
          code = '710'
          ind1 = '2'
          sfs = [
                  ['a', name['primary_name']],
                  ['b', name['subordinate_name_1']],
                  ['b', name['subordinate_name_2']],
                  ['n', name['number']],
                  ['g', name['qualifier']],
                ]
  
        when 'agent_person'
          joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
          name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
          ind1 = name['name_order'] == 'direct' ? '0' : '1'
          code = '700'
          sfs = [
                  ['a', name_parts],
                  ['b', name['number']],
                  ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
                  ['q', name['fuller_form']],
                  ['d', name['dates']],
                  ['g', name['qualifier']],
                ]
  
        when 'agent_family'
          ind1 = '3'
          code = '700'
          sfs = [
                  ['a', name['family_name']],
                  ['c', name['prefix']],
                  ['d', name['dates']],
                  ['g', name['qualifier']],
                ]
        end
      end
      
      if role == 'source'
        joint = name['name_order'] == 'direct' ? ', ' : ' '
        ind1 = '1'
        ind2 = ' '
        code = '561'
        
        case creator['agent_type']
        
          when 'agent_corporate_entity'
            ownership_language = 'Gift of '
            sfs = [
                    ['a', ownership_language +  name['primary_name']],
                  ]    

          when 'agent_person'
            sfs = [
                    ['a', ownership_language +  [name['rest_of_name'], name['primary_name']].reject{|i| i.nil? || i.empty?}.join(joint)],
                  ]
          
          when 'agent_family'
            sfs = [
                    ['a', ownership_language +  name['family_name']],
                  ]          
        end
      end
      sfs << relator_sf
      df(code, ind1, ind2).with_sfs(*sfs)
    end
    
  end
  
  # switch the order of the extents for local rules
  # add the 300|b and 300|c to the extents
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
      
      # 300|b
      physdesc = ext['physical_details']
      
      # 300|c
      dimensions = ext['dimensions']

      df!('300').with_sfs(
                           ['a', extent],
                           ['b', physdesc],
                           ['c', dimensions]
                          )
    end
  end
  
  # never export the processing notes
  def handle_notes(notes)

    notes.each do |note|

      prefix =  case note['type']
                when 'dimensions'; "Dimensions"
                when 'physdesc'; "Physical Description note"
                when 'materialspec'; "Material Specific Details"
                when 'physloc'; "Location of resource"
                when 'phystech'; "Physical Characteristics / Technical Requirements"
                when 'physfacet'; "Physical Facet"
                # when 'processinfo'; "Processing Information"
                when 'separatedmaterial'; "Materials Separated from the Resource"
                else; nil
                end

      marc_args = case note['type']

                  when 'arrangement', 'fileplan'
                    ['351','b']
                  when 'odd', 'dimensions', 'physdesc', 'materialspec', 'physloc', 'phystech', 'physfacet', 'separatedmaterial'
                    ['500','a']
                  when 'accessrestrict'
                    ['506','a']
                  when 'scopecontent'
                    ['520', '2', ' ', 'a']
                  when 'abstract'
                    ['520', '3', ' ', 'a']
                  when 'prefercite'
                    ['524', '8', ' ', 'a']
                  when 'acqinfo'
                    ind1 = note['publish'] ? '1' : '0'
                    ['541', ind1, ' ', 'a']
                  when 'relatedmaterial'
                    ['544','a']
                  when 'bioghist'
                    ['545','a']
                  when 'custodhist'
                    ind1 = note['publish'] ? '1' : '0'
                    ['561', ind1, ' ', 'a']
                  when 'appraisal'
                    ind1 = note['publish'] ? '1' : '0'
                    ['583', ind1, ' ', 'a']
                  when 'accruals'
                    ['584', 'a']
                  when 'altformavail'
                    ['535', '2', ' ', 'a']
                  when 'originalsloc'
                    ['535', '1', ' ', 'a']
                  when 'userestrict', 'legalstatus'
                    ['540', 'a']
                  when 'langmaterial'
                    ['546', 'a']
                  else
                    nil
                  end

      unless marc_args.nil?
        text = prefix ? "#{prefix}: " : ""
        text += ASpaceExport::Utils.extract_note_text(note)
        df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)])
      end

    end
  end
  
  # override to change finding aid 856 language
  def handle_ead_loc(ead_loc)
    df('856', '4', '2').with_sfs(
                                  ['z', "View the finding aid for this resource."],
                                  ['u', ead_loc]
                                )
  end
  
  # add in the material type 245|b
  def handle_title_extras(user_defined)
    if user_defined['text_4']
      df('245', '1', '0').with_sfs(['b', user_defined['text_4'].downcase])
    end
  end
  
end


class MARCSerializer < ASpaceExport::Serializer 
 
  private

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

class EADSerializer < ASpaceExport::Serializer
  
  # we're patching this method to deal with the genreform in the unittitle
  def stream(data)
    @stream_handler = ASpaceExport::StreamHandler.new
    @fragments = ASpaceExport::RawXMLHandler.new
    @include_unpublished = data.include_unpublished?
    @include_daos = data.include_daos?
    @use_numbered_c_tags = data.use_numbered_c_tags?
    @id_prefix = I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')

    doc = Nokogiri::XML::Builder.new(:encoding => "UTF-8") do |xml|
      begin

      ead_attributes = {
        'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
        'xsi:schemaLocation' => 'urn:isbn:1-931666-22-9 http://www.loc.gov/ead/ead.xsd',
        'xmlns:xlink' => 'http://www.w3.org/1999/xlink'
      }

      if data.publish === false
        ead_attributes['audience'] = 'internal'
      end

      xml.ead( ead_attributes ) {

        xml.text (
          @stream_handler.buffer { |xml, new_fragments|
            serialize_eadheader(data, xml, new_fragments)
          })

        atts = {:level => data.level, :otherlevel => data.other_level}
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
              xml.unittitle  {
                sanitize_mixed_content(val, xml, @fragments)
                # genreform patch
                if data.user_defined && data.user_defined['text_4']
                  genreformtxt = data.user_defined['text_4']
                  xml.genreform{xml.text(genreformtxt)}
                end
                }
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
end
