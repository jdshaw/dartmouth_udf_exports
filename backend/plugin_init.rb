require_relative 'lib/aspace_patches'
require_relative 'lib/ead_user_defined_field_serialize'
require_relative 'lib/marc_user_defined_field_serialize'

# Register our custom serialize steps.
EADSerializer.add_serialize_step(EADUserDefinedFieldSerialize)
MARCSerializer.add_decorator(MARCUserDefinedFieldSerialize)
