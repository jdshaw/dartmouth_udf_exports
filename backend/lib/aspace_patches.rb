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
  
  # override to change finding aid 555 & 856 language
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
