#--
# Copyright (c) 2014, Flinders University, South Australia. All rights reserved.
# Contributors: eResearch@Flinders, Library, Information Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#++ 

##############################################################################
# A class to represent a DSpace community
class Community
  # Define objects *before* they are referenced by 'required' files
  ERA_YEAR = "2012"

  require 'xmlsimple'
  require 'faster_csv'
  require 'collection'
  require 'object_extra'

  # Select if you want subcommunities to be ERA clusters or 2-digit FOR codes
  SUB_COMMUNITY_TYPE = :for2digit		# :cluster or :for2digit

  # Lookup table from ERA cluster-abreviations to cluster-descriptions
  CLUSTER_ABBREVIATION2DESCRIPTION = {
    'PCE' => 'Physical, Chemical and Earth Sciences',
    'HCA' => 'Humanities and Creative Arts',
    'EE'  => 'Engineering and Environmental Sciences',
    'EHS' => 'Education and Human Society',
    'EC'  => 'Economics and Commerce',
    'MIC' => 'Mathematical, Information and Computing Sciences',
    'BB'  => 'Biological and Biotechnological Sciences',
    'MHS' => 'Medical and Health Sciences',
  }

  # A number to be associated with each cluster
  CLUSTER_ABBREVIATION2NUMBER = {
    'PCE' => 1,
    'HCA' => 2,
    'EE'  => 3,
    'EHS' => 4,
    'EC'  => 5,
    'MIC' => 6,
    'BB'  => 7,
    'MHS' => 8,
  }

  # Lookup table from 2-digit Field of Research (FOR) codes to FOR Descriptions
  FOR_CODE2DESCRIPTION = {
    "01" => "Mathematical Sciences",
    "02" => "Physical Sciences",
    "03" => "Chemical Sciences",
    "04" => "Earth Sciences",
    "05" => "Environmental Sciences",
    "06" => "Biological Sciences",
    "07" => "Agricultural and Veterinary Sciences",
    "08" => "Information and Computing Sciences",
    "09" => "Engineering",
    "10" => "Technology",
    "11" => "Medical and Health Sciences",
    "12" => "Built Environment and Design",
    "13" => "Education",
    "14" => "Economics",
    "15" => "Commerce, Management, Tourism and Services",
    "16" => "Studies in Human Society",
    "17" => "Psychology and Cognitive Sciences",
    "18" => "Law and Legal Studies",
    "19" => "Studies in Creative Arts and Writing",
    "20" => "Language, Communication and Culture",
    "21" => "History and Archaeology",
    "22" => "Philosophy and Religious Studies",
  }


  # This class assumes the XML 'name' element:
  # - is mandatory (hence it does not appear in this list) and
  # - its value is unique.
  #
  # The XML elements in this list are optional for a Community.
  OPTIONAL_ELEMENTS = %w{ description intro copyright sidebar }

  # Populate all sub-communities with the optional XML elements
  # given below. Note that 'name' is a mandatory XML element
  # and must not appear in this hash.
  XML_ELEMENTS = {
    'description' => "Flinders' research in {{LOOKUP_FOR_2DIGIT_NAME}} as reported for ERA #{ERA_YEAR}.",
    'intro'       => "<center><p>This community contains Flinders' research in {{LOOKUP_FOR_2DIGIT_NAME}} that has been collected for ERA #{ERA_YEAR}.</p>
<p>Where copyright and other restrictions allow, full text content is available.</p></center>",
=begin
    'copyright'   => 'Sub-community copyright text',
    'sidebar'     => 'Sub-community sidebar text'
=end
  }

  # Regular expressions for replacing tokens within a string.
  # Tokens can comprise alpha-numerics and underscores.
  CSV_FIELD_REGEX = /\{\{CSV_FIELD_([[:alnum:]_]+)\}\}/
  LOOKUP_REGEX = /\{\{LOOKUP_([[:alnum:]_]+)\}\}/

  # Exit codes for errors
  ERROR_BASE = 8
  ERROR_XML_ELEMENT_NAME		= ERROR_BASE + 1
  ERROR_CLUSTER_CODE_LOOKUP		= ERROR_BASE + 2
  ERROR_FORCODE2_LOOKUP			= ERROR_BASE + 3
  ERROR_SUB_COMMUNITY_TYPE		= ERROR_BASE + 4

  attr_reader :name, :child_comms, :child_colls

  ############################################################################
  # Creates a Community object.
  #
  # Invocation exmaple:
  #   optional_elements = {
  #     'description' => 'My description',
  #     'intro'       => 'My introduction'
  #   }
  #   c = Community.new('My community name', optional_elements)
  def initialize(name, optional_xml_elements={}, csv_fields={})
    @name = name		# String
    @child_comms = []		# List of Community objects
    @child_colls = []		# List of Collection objects

    @opts = optional_xml_elements
    @opts.each_key{|k|
      unless OPTIONAL_ELEMENTS.include?(k)
        STDERR.puts "ERROR: XML element <#{k}> is not permitted as part of a #{self.class} in the object: #{inspect_more}"
        exit(ERROR_XML_ELEMENT_NAME)
      end
    }
    @csv_fields = csv_fields
    replace_token_in_optional_xml_elements
  end

  ############################################################################
  # If any values in the @opts hash contain tokens, this method replaces
  # such tokens with the corresponding replacement string. ie. This method
  # updates @opts.
  def replace_token_in_optional_xml_elements
    return if @opts.empty? || @csv_fields.empty?

    @opts = @opts.deep_copy
    @opts.each_value{|str| self.class.replace_token_in_string(str, @csv_fields) }
  end

  ############################################################################
  # This method replaces special tokens within a string with other text.
  # A token looks like "{{PREFIX_KEY}}". For a PREFIX of "CSV_FIELD",
  # the token is replaced by the CSV field csv_fields[KEY] (where
  # csv_fields is the hash in the second argument and KEY is a symbol 
  # representing the CSV column name). Examples of such tokens include:
  # - "{{CSV_FIELD_cluster_abbrev}}" for csv_fields[:cluster_abbrev]
  # - "{{CSV_FIELD_for_code}}" for csv_fields[:for_code]
  # - "{{CSV_FIELD_for_title}}" for csv_fields[:for_title]
  #
  # For a PREFIX of "LOOKUP", the token is replaced by some lookup
  # related to one of the CSV fields. Examples of such tokens include:
  # - "{{LOOKUP_CLUSTER_NAME}}" for the cluster name associated
  #   with csv_fields[:cluster_abbrev]
  # - "{{LOOKUP_FOR_2DIGIT}}" for the 2-digit FOR code string
  #   associated with the 4-digit FOR code, csv_fields[:for_code]
  # - "{{LOOKUP_FOR_2DIGIT_NAME}}" for the name associated with
  #   the 2-digit FOR code
  #
  # This method returns a copy of the updated string.

  def self.replace_token_in_string(string, csv_fields)
    # Replace each match with corresponding CSV field
    string.gsub!(CSV_FIELD_REGEX){|match| csv_fields[$1.to_sym] }

    # Replace each match with lookup of corresponding CSV field
    string.gsub!(LOOKUP_REGEX){|match|
      case $1
      when 'CLUSTER_NAME'
        CLUSTER_ABBREVIATION2DESCRIPTION[ csv_fields[:cluster_abbrev] ]
      when 'FOR_2DIGIT'
        csv_fields[:for_code][0,2]
      when 'FOR_2DIGIT_NAME'
        FOR_CODE2DESCRIPTION[ csv_fields[:for_code][0,2] ]
      end
    }
    string
  end

  ############################################################################
  # Under this community, this method loads a list of sub-communities
  # and collections belonging to those sub-communities from a CSV file.
  def load_csv(fname, faster_csv_options={})
    opts = {
      :col_sep => ',',
      # It is not advisible to override the values below with those
      # from faster_csv_options (as this method assumes these values)
      :headers => true,
      :header_converters => :symbol,
    }.merge!(faster_csv_options)

    count = 0
    FasterCSV.foreach(fname, opts) {|line|
      count += 1
      puts "\n#{count} <<#{line.to_s.chomp}>>" if MDEBUG.include?(__method__)
      next if skip_csv_line?(line)

      # Get or create-and-append the sub-community derived from this
      # CSV-line under THIS community object.
      # Duplicate sub-community names are not permitted under THIS
      # community object.
      comm_name = community_name(line, count)
      comm = self.get_community_with_name(comm_name)
      unless comm
        comm = Community.new(comm_name, XML_ELEMENTS, line)
        self.append_community(comm)
      end

      # Get or create-and-append the collection derived from this
      # CSV-line under the ABOVE sub-community object, comm.
      # Duplicate collection names are not permitted under the ABOVE
      # sub-community object, comm.
      coll_name = collection_name(line, count)
      coll = comm.get_collection_with_name(coll_name)
      unless coll
        coll = Collection.new(coll_name, Collection::XML_ELEMENTS, line)
        comm.append_collection(coll)
      end
    }
  end

  ############################################################################
  # *_Customise_* this method:
  # Returns true to skip processing of csv_line. You can customise this method
  # to return true in your choice of conditions. Eg. to never skip processing
  # of any CSV line, replace the body of this method with: false
  def skip_csv_line?(csv_line)
    csv_line[:for_code].length == 2	# Skip 2 digit FOR codes
    #false				# Uncomment this line to process all CSV lines
  end

  ############################################################################
  # *_Customise_* this method:
  # Returns community name for this CSV line. You can customise this method
  # to return the name of your choice.
  def community_name(csv_line, csv_line_count=nil)
    case SUB_COMMUNITY_TYPE

    when :cluster
      unless CLUSTER_ABBREVIATION2DESCRIPTION[ csv_line[:cluster_abbrev] ]
        STDERR.puts "Method: #{__method__}"
        STDERR.puts "ERROR:  Lookup for cluster code '#{csv_line[:cluster_abbrev]}' not found. See line:"
        STDERR.printf "  %s%s\n", (csv_line_count ? "[#{csv_line_count}] " : ''), csv_line.to_s.chomp
        exit(ERROR_CLUSTER_CODE_LOOKUP)
      end
      comm_name = sprintf("Cluster %d - %s",
       CLUSTER_ABBREVIATION2NUMBER[ csv_line[:cluster_abbrev] ],
       CLUSTER_ABBREVIATION2DESCRIPTION[ csv_line[:cluster_abbrev] ])

    when :for2digit
      for2digit = csv_line[:for_code][0,2]
      unless FOR_CODE2DESCRIPTION[for2digit]
        STDERR.puts "Method: #{__method__}"
        STDERR.puts "ERROR:  Lookup for 2-digit FOR code '#{for2digit}' not found. See line:"
        STDERR.printf "  %s%s\n", (csv_line_count ? "[#{csv_line_count}] " : ''), csv_line.to_s.chomp
        exit(ERROR_FORCODE2_LOOKUP)
      end
      comm_name = sprintf "%s - %s",
        for2digit, FOR_CODE2DESCRIPTION[for2digit]

    else
      STDERR.puts "Method: #{__method__}"
      STDERR.puts "ERROR: SUB_COMMUNITY_TYPE '#{SUB_COMMUNITY_TYPE}' not recognised."
      exit(ERROR_SUB_COMMUNITY_TYPE)

    end
    comm_name
  end

  ############################################################################
  # *_Customise_* this method:
  # Returns collection name for this CSV line. You can customise this method
  # to return the name of your choice.
  def collection_name(csv_line, csv_line_count=nil)
    "#{csv_line[:for_code]} - #{csv_line[:for_title]}"	# FOR code + FOR title
  end

  ############################################################################
  # Appends a community object to the list of child-communities
  def append_community(comm)
    @child_comms << comm
  end

  ############################################################################
  # Appends a collection object to the list of child-collections
  def append_collection(coll)
    @child_colls << coll
  end

  ############################################################################
  # Returns the first community object from the list of child-communities
  # having a name matching the specified argument. Returns nil if there
  # is no matching name.
  def get_community_with_name(name)
    @child_comms.each{|c| return c if c.name == name}
    nil
  end

  ############################################################################
  # Returns the first collection object from the list of child-collections
  # having a name matching the specified argument. Returns nil if there
  # is no matching name.
  def get_collection_with_name(name)
    @child_colls.each{|c| return c if c.name == name}
    nil
  end

  ############################################################################
  # A method which returns a hash representing
  # this community object in a format which is compatible
  # with the XmlSimple class.
  #
  # From outside the class, invoke this method instead of
  # struct_hash().
  def top_struct_hash
    {
      'community' => struct_hash
    }
  end

  ############################################################################
  # A recursive helper-method which returns a hash representing
  # this community object in a format which is compatible
  # with the XmlSimple class. The method is recursive
  # because this community may itself contain other
  # communities.
  #
  # This helper-method is not expected to be invoked externally
  # because it omits the outer 'community' hash-key representing
  # the top-level <community> XML element. Hence
  # from outside the class, invoke top_struct_hash() instead.
  def struct_hash
    struct = {
      'name' => @name,
    }.merge!(@opts)

    struct['community'] = []
    @child_comms.each{|c|
      struct['community'] << c.struct_hash
    }

    struct['collection'] = []
    @child_colls.each{|c|
      struct['collection'] << c.struct_hash
    }
    struct
  end

  ############################################################################
  # A method to convert this community object (including
  # all communities and collections contained in it) into
  # (DSpace 'structure-builder' compatible) XML.
  def to_xml(xmlsimple_opts={})
    opts = {
      'AttrPrefix' => true,
      'rootname' => 'import_structure',
    }.merge!(xmlsimple_opts)
    XmlSimple.xml_out(top_struct_hash, opts)
  end

  ############################################################################
  # Convert this object to a string
  def to_s
    @name
  end

  ############################################################################
  # Inspect this object
  #--
  # FIXME: This output is difficult to read. It would be
  # better to display the community tree-structure using
  # indentation.
  def inspect
    "\n<<#{self.class}::#{@name}>>;\n  #{@name}::Comms: #{@child_comms.inspect};\n  #{@name}::Colls: #{@child_colls.inspect} "
  end

  ############################################################################
  # Inspect all the details (but without showing child
  # communities and collections)
  def inspect_more_without_children
    "\n<<#{self.class}::#{@name}>>;\n  #{@opts.inspect}"
  end

  ############################################################################
  alias inspect_more  inspect_more_without_children
end

