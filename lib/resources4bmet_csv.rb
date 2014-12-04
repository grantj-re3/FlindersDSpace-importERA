#--
# Copyright (c) 2014, Flinders University, South Australia. All rights reserved.
# Contributors: eResearch@Flinders, Library, Information Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#++

require 'dspace_pg_utils'

##############################################################################
# A class which provides the public method extra_csv_fields() where the
# extra CSV fields are for debugging purposes and require access to
# database resources as used in the handle table ie. items, collections
# and communities, plus RMIDs. To minimise repetition of SQL access, we
# cache item, collection and RMID details.
##############################################################################
class Resources4BmetCsv
  include DSpacePgUtils

  # Make this constant different from NULL (Ruby nil) lookup value returned
  # from the database. Hence if hash lookup by handle results in this
  # string, then the result is not stored in the cache. Otherwise we will
  # look in the database and store the result (which may be nil). 
  DEFAULT_LOOKUP_STRING = ''

  ############################################################################
  # Create a new object which:
  # - caches any new item info
  # - caches any new collection info
  # which is requested via the extra_fields() method.
  ############################################################################
  def initialize
    @item_names = Hash.new(DEFAULT_LOOKUP_STRING)	# Cache for item info
    @rmids = Hash.new(DEFAULT_LOOKUP_STRING)		# Cache for RMID info
    @col_names = Hash.new(DEFAULT_LOOKUP_STRING)	# Cache for collection info

    @db_conn = PG::Connection.connect(DB_CONNECT_INFO)	# Connect to the DB
  end

  ############################################################################
  # Close the database connection
  ############################################################################
  def close
    @db_conn.close if @db_conn
  end

  ############################################################################
  # Return extra CSV fields, in particular:
  # - item name
  # - collection name
  ############################################################################
  def extra_csv_fields(item_hdl, col_hdls, csv_delimiter, csv_quote)
    item_name, rmid = lookup_item_name(item_hdl)
    col_names = col_hdls.inject([]){|a,col_hdl| a << lookup_collection_name(col_hdl)}

    "#{csv_delimiter}#{csv_quote}#{rmid}#{csv_quote}" +
      "#{csv_delimiter}#{csv_quote}#{item_name}#{csv_quote}" +
      "#{csv_delimiter}#{csv_quote}#{col_names.join(VALUE_DELIMITER)}#{csv_quote}"
  end

  ############################################################################
  # Return the item name by performing a lookup-by-handle in the database.
  ############################################################################
  def lookup_item_name(handle)
    # Return the cached version if possible
    return [ @item_names[handle], @rmids[handle] ] unless @item_names[handle] == DEFAULT_LOOKUP_STRING

    sql = <<-SQL_LOOKUP_ITEM_NAME.gsub(/^\t*/, '')
	select
	  mdv.item_id,
	  mdv.text_value as title,
	  (select text_value from metadatavalue where item_id=mdv.item_id and metadata_field_id = 
	    (select metadata_field_id from metadatafieldregistry where element='identifier' and qualifier='rmid')
	  ) rmid
	from metadatavalue mdv
	where
	  mdv.item_id = (select resource_id from handle where handle='#{handle}' and resource_type_id=#{RESOURCE_TYPE_IDS[:item]}) and
	  mdv.metadata_field_id = (select metadata_field_id from metadatafieldregistry where element='title' and qualifier is null)
    SQL_LOOKUP_ITEM_NAME
    db_connect{|conn|
      conn.exec(sql){|result|
        if result.ntuples == 1
          result.each{|row|
            @item_names[handle] = row['title']	# Add to cache (can be nil)
            @rmids[handle] = row['rmid']	# SQL above assumes 1 RMID per item
          }
        else
          STDERR.puts "Quitting: #{result.ntuples} item-titles found for handle #{handle} (but expected 1)"
          exit 6
        end
      }
    }
    [ @item_names[handle], @rmids[handle] ]
  end

  ############################################################################
  # Return the collection name by performing a lookup-by-handle in the database.
  # Since collections in ERA reporting years are likely to have the same
  # name (ie. 4-digit FOR code and description) and the parent community
  # is also likely to have the same name (ie. ERA cluster name or 2-digit
  # FOR code and description) then we will include the grandparent
  # community name in the return string.
  ############################################################################
  def lookup_collection_name(handle)
    # Return the cached version if possible
    return @col_names[handle] unless @col_names[handle] == DEFAULT_LOOKUP_STRING

    sql = <<-SQL_LOOKUP_COLLECTION_NAME.gsub(/^\t*/, '')
	select
	  c.name,
	  (select name from community where community_id=
	    (select parent_comm_id from community2community where child_comm_id=
	      (select community_id from community2collection com2c where com2c.collection_id=c.collection_id)
	    )
	  ) grandparent_comm_name
	from collection c
	where c.collection_id = (select resource_id from handle where handle='#{handle}' and resource_type_id=#{RESOURCE_TYPE_IDS[:collection]});
    SQL_LOOKUP_COLLECTION_NAME
    db_connect{|conn|
      conn.exec(sql){|result|
        if result.ntuples == 1
          result.each{|row| @col_names[handle] = "#{row['name']} {#{row['grandparent_comm_name']}}"}	# Add to cache (can be nil)
        else
          STDERR.puts "Quitting: #{result.ntuples} collection-titles found for handle #{handle} (but expected 1)"
          exit 6
        end
      }
    }
    @col_names[handle]
  end

end

