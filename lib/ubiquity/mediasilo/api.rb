require 'rubygems'
require 'logger'
require 'json'

require 'ubiquity/mediasilo/api/connection'
require 'ubiquity/mediasilo/api/response'
require 'ubiquity/mediasilo/api/request'

module Ubiquity

  module MediaSilo

    class API

      DEFAULT_HOST_ADDRESS = 'https://api2.mediasilo.com'
      DEFAULT_RETURN_FULL_RESPONSE = false
      DEFAULT_TIMEOUT = 6000
      DEFAULT_PAGE_SIZE = 50

      attr_accessor :connection, :request, :response, :session_key

      attr_accessor :return_full_response_by_default
      attr_accessor :default_page_size

      def initialize(args = { })
        @connection = Connection.new(args)

        @return_full_response_by_default = args.fetch(:return_full_response, DEFAULT_RETURN_FULL_RESPONSE)
        @default_page_size = args.fetch(:default_page_size, DEFAULT_PAGE_SIZE)
      end

      # Forces all eligible hash keys to lowercase symbols
      #
      # @param [Hash] hash
      def normalize_hash_keys(hash)
        return hash unless hash.is_a?(Hash)
        Hash[ hash.dup.map { |k,v| [ ( k.respond_to?(:downcase) ? k.downcase.to_sym : k ), v ] } ]
      end

      def normalize_argument_hash_keys(hash)
        return hash unless hash.is_a?(Hash)
        Hash[ hash.dup.map { |k,v| [ ( k.respond_to?(:to_s) ? k.to_s.gsub('_', '').downcase : k ), v ] } ]
      end

      def normalize_parameter_name(name)
        name.respond_to?(:to_s) ? name.to_s.gsub('_', '').downcase : name
      end

      # @param [Array] params
      # @param [Hash]  args
      # @param [Hash]  options
      def process_additional_parameters(params, args, options = { })
        args = normalize_argument_hash_keys(args)
        add_params = { }
        params.each do |k|
          if k.is_a?(Hash) then
            param_name = normalize_parameter_name(k[:name])
            has_key = args.has_key?(param_name)
            has_default_value = k.has_key?(:default_value)
            next unless has_key or has_default_value
            value = has_key ? args[param_name] : k[:default_value]
          else
            param_name =  normalize_parameter_name(k)
            next unless args.has_key?(param_name)
            value = args[param_name]
          end
          #if value.is_a?(Array)
          #  param_options = k[:options] || { }
          #  join_array = param_options.fetch(:join_array, true)
          #  value = value.join(',') if join_array
          #end
          add_params[param_name] = value
        end
        add_params
      end

      # @param [Hash] params Parameters to merge into
      # @return [Hash]
      def merge_additional_parameters(params, add_params, args, options = { })
        params.merge(process_additional_parameters(add_params, args, options))
      end

      # @param [String] api_method
      # @param [Hash] api_method_arguments
      # @param [Hash] options
      # @option options [Boolean] :add_session_key (true)
      # @return [Response]
      def call_method(api_method, api_method_arguments = { }, options = { })
        _options = { :connection => connection }.merge(options)
        _return_full_response = options.fetch(:return_full_response, return_full_response_by_default)

        if options[:paginated]
          api_method_arguments
        end

        api_method_arguments[:session] ||= session_key if options.fetch(:add_session_key, true)
        @request = API::Request.new(api_method, api_method_arguments, _options)
        #connection.send_api_request(@request)
        @response = request.send

        logger.debug { "REQUEST: #{request.connection.http_request_as_hash.inspect}"}
        logger.debug { "RESPONSE: #{response.raw.body}" }
        return response if _return_full_response
        response.result
      end

      def success?
        response ? response.success? : nil
      end

      def error_message
        response.respond_to?(:error_message) ? response.error_message : nil
      end

      def initialize_session(credentials)
        response = user_login(credentials)
        _session_key = response.respond_to?(:[]) ? response['SESSION'] : response
        set_session_key(_session_key)
        session_key
      end

      def set_session_key(session_key)
        @session_key = session_key
        connection.session_key = session_key if connection
      end

      # Used to convert a standard key => value pair into a hash formatted for new metadata
      #   { 'key' => key, 'value' => value} and then converts it to json
      #
      # @param [Array<Hash>, Hash] metadata
      # @return [String] JSON formatted string containing the metadata
      def metadata_create_to_json(metadata)
        mediasilo_metadata = metadata.is_a?(Hash) ? metadata.map { |k,v| { 'key' => k, 'value' => v } } : metadata
        JSON.generate(mediasilo_metadata)
      end

      # ############################################################################################################## #
      # @!group API Methods


      # Attaches a tag to an asset, if the tag does not exist then it is created and then attached to the asset.
      # Requires either a tagid or a tagname.
      #
      # @param [String] asset_uuid The asset UUID's you want to attach the tags to
      # @param [Hash] args
      # @option args [Integer, String, Array<Integer>, Array<String>] :tagid The ID's of the tags to attach to the
      #   asset, more efficient then tagname
      # @option args [String, Array<String>] :tagname Tags you want attached to the asset, they are created if they do
      #   not exist, less efficient then using ID's
      def asset_add_tag(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        add_params = [ :tagid, :tagname ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.AddTag', params)
      end

      # Advanced search allows you to search your assets using logic blocks, the format for the searchquery is based on
      # a Amazon CloudSearch query
      #
      # @param [String] search_query The search query string
      #   @see http://docs.amazonwebservices.com/cloudsearch/latest/developerguide/searching.html Amazon CloudSearch
      #   query guide
      #
      #   The SEARCHQUERY term must be in parenthesis '()' and must start with one of the following; 'and', 'or', 'not'
      #
      #   example1: (and title:'test')
      #   example2: (or title:'test')
      #   example3: (not title:'test')
      #   example4: (and filename:'Cook' title:'Cook')
      #   example5: (or filename:'Energy' title:'Cook')
      #
      #   approvalstatus (uint) 0=none,1=pending,2=approved,3=rejected,4=complete
      #   averagerating (uint) 0 to 5
      #   comments (text)
      #   datecreated (uint) unix date
      #   datemodified (uint) unix date
      #   description (text)
      #   duration (uint) seconds
      #   filename (text)
      #   hasapprovals (literal) 'true' or 'false'
      #   hascomments (literal) 'true' or 'false'
      #   hasrating (literal) 'true' or 'false'
      #   hastranscript (literal) 'true' or 'false'
      #   height (uint)
      #   metadatakeys (text)
      #   metadatamatch (literal) key===value
      #   metadatavalues (text)
      #   rating (uint)
      #   size (uint)
      #   tags (text)
      #   tags_exact (text)
      #   title (text)
      #   transcript (text)
      #   transcriptstatus (literal) 'na' or 'available' or 'pending'
      #   uploaduser (text)
      #   width (uint)
      #
      #   Additional Examples:
      #
      #     Get All Assets:
      #       '(or size:0 (not size:0))'
      #       '(or (not size:0) (or size:0) )'
      #       %q((not filename:''))
      #
      #     Metadata Search:
      #       %q((and metadatamatch:'Metadata Field Name===Any Metadata Value'))
      #
      #     Filename and Title Contain a String:
      #       %q((and filename:'Cook' title:'Cook'))
      #       %q((and filename:'Cook' (and title:'Cook')))
      #
      #     Filename or Title Contain a String:
      #       %q((or filename:'Energy' title:'Cook'))
      #
      # @param [Hash] args
      # @option args [Integer] :page The page of assets to return starting at 0
      #   IMPORTANT TO NOTE THAT THIS IS THE ONLY API CALL THAT STARTS AT PAGE 0
      # @option args [Integer] :pagesize Number of assets to return per a page
      # @option args [Integer] :folderid The ID of a folder to limit the search to
      # @option args [Integer] :projectid THe ID of a project ot limit the search to
      # @option args [Integer, <Integer>] :tags List of tag ID's to use with the tag filter on resulting assets
      # @option args [String] :orderby ('date_desc') The order to return the assets in, default is date_desc
      #   (date_desc, date_asc, title_asc, title_desc, filename_asc, filename_desc,size_asc,size_desc)
      # @option args [String] :tagfilter The tag filter conditional, "and", "or", "not"
      # @option args [String, <String>] :types The asset types to return, all are returned by default
      #   (video,image,document,archive,audio)
      # @option args [Boolean] :searchglobal
      # @return [Array]
      def asset_advanced_search(search_query, args = { })
        params = {
          :searchquery => search_query
        }
        add_params = [ { :name => :page, :default_value => 0 },
                       { :name => :pagesize, :default_value => default_page_size },
                       :folderid, :projectid, :tags, :tagfilter, :orderby, :types, :searchglobal ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.AdvancedSearch', params, :primary_key_name => 'ASSETS', :paginated => true,
                    :pagination_first_page => 0)
      end

      # @param [String, <String>] asset_uuid The UUID of the asset to make a copy of
      # @param [Hash] args
      # @option args [Integer] :folderid
      # @option args [Integer] :projectid
      # @option args [Boolean] :copytags
      # @option args [Boolean] :copycomments
      # @option args [Boolean] :copymetadata
      def asset_copy(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid
        }
        add_params = [ :folderid, :projectid, :copytags, :copycomments, :copymetadata ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.Copy', params)
      end

      # Creates an asset in MediaSilo and proxy from a valid file URL
      #
      # @param [String] url
      # @param [Hash] args
      # @option args [Integer] :projectid The ID of the project you want the asset placed in, can be helpful when you
      #   reuse project names
      # @option args [Integer] :folderid The ID of the folder you want the asset placed in, can be helpful when you
      #   reuse folder names
      # @option args [String] :project The name of a project you want the asset placed in, if one is not supplied then
      #   the asset will exist in the library only
      # @option args [String] :folder The name of the folder you want the asset placed in, if a project is also passed
      #   then only subfolders in that project are used
      def asset_create(url, args = { })
        params = {
          :url => url
        }
        add_params = [ :projectid, :folderid, :project, :folder ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.Create', params)
      end

      # Creates an externally hosted asset in MediaSilo
      #
      # An external asset means that all files associated with the asset (source, thumbnails, etc) are stored externally
      # and must be valid and provided to this call. All file URL's must contain the filename and an extension, but can
      # also contain URL variables if needed. All URL's should be URL encoded and use the HTTP or HTTPS protocol.
      #
      # Different inputs are required for different asset types, but a project or folder is required for all:
      #
      # for VIDEO assets the following is required: source,proxy,thumbnaillarge,thumbnailsmall,height,width,durationseconds
      # for IMAGE assets the following is required: source,proxy,thumbnailsmall
      # for AUDIO assets the following is required: source,proxy
      # for DOCUMENT assets the following is required: source
      #
      # @param [String] source_url The URL of the source asset
      # @param [Hash] args
      # @option args [Integer] :projectid The PROJECT ID you want the asset placed in
      # @option args [Integer] :folderid The FOLDER ID you want the asset placed in
      # @option args [String] :proxy The URL of the proxy asset
      # @option args [String] :thumbnailsmall The URL of the small thumbnail
      # @option args [String] :thumbnaillarge The URL of the large thumbnail
      # @option args [Integer] :width The WIDTH of the video asset
      # @option args [Integer] :height The HEIGHT of the video asset
      # @option args [Integer] :durationseconds The DURATION of the video asset in SECONDS
      # @option args [String] :streamer The streamer URL to be used when streaming the proxy
      def asset_create_external(source_url, args = { })
        params = {
          :source => source_url
        }
        add_params = [ :projectid, :folderid, :proxy, :thumbnailsmall, :thumbnaillarge, :height, :width, :durationseconds ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.CreateExternal', params)
      end



      # Delete an asset and all associated data. It is recommended to also pass the "removeall" attribute if all
      #   instances of an asset should be removed.
      #
      # @param [String, <String>] asset_uuid The UUID's of the assets you want deleted
      # @param [Hash] args
      # @option args [Boolean] :removeall If true it will delete all instances of this asset and all associated data
      #   and remove the files from storage
      def asset_delete(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid, #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
          :removeall => 1
        }
        add_params = [ :removeall ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.Delete', params)
      end

      # Edits the corresponding assets
      #
      # @param [String, Array<String>] asset_uuid The UUID's of the assets you want to edit
      # @param [Hash] args
      # @option args [Integer] :width Allows you to adjust the stored asset width, video only
      # @option args [Integer] :height Allows you to adjust the stored asset height, video only
      # @option args [String] :description The value you want description changed to
      # @option args [String] :title The value you want title changed to
      def asset_edit(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid
        }
        add_params = [ :width, :height, :description, :title ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.Edit', params)
      end

      # Edits the corresponding external asset, not all fields apply to all asset types.
      #
      # @param [String] asset_uuid The UUID of the external asset you want to edit
      # @param [Hash] args
      # @option args [Integer] :projectid The PROJECT ID you want the asset placed in
      # @option args [Integer] :folderid The FOLDER ID you want the asset placed in
      # @option args [String] :proxy The URL of the proxy asset
      # @option args [String] :thumbnailsmall The URL of the small thumbnail
      # @option args [String] :thumbnaillarge The URL of the large thumbnail
      # @option args [Integer] :width The width of the source file
      # @option args [Integer] :height The height of the source file
      # @option args [Integer] :durationseconds The DURATION of the video asset in SECONDS
      # @option args [String] :streamer The streamer URL to be used when streaming the proxy
      def asset_edit_external(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid
        }
        add_params = [ :proxy, :thumbnailsmall, :thumbnaillarge, :height, :width, :durationseconds, :streamer ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.EditExternal', params)
      end

      # Updates the corresponding assets approval status
      #
      # @param [String, Array<String>] asset_uuid One or more UUID's of the assets you want to update approval status
      #   for
      # @param [String] status The status you want to set the approval status to.
      #   Valid values are 'none, approved, rejected'
      def asset_edit_approval_status(asset_uuid, status)
        params = {
          :uuid => asset_uuid,
          :status => status
        }
        call_method('Asset.EditApprovalStatus', params)
      end

      # Returns the assets in the corresponding folder
      #
      # @param [Integer] folder_id The ID of the folder you want to retrieve assets from
      # @param [Hash] args
      # @option args [Integer] :page The page of assets to return starting at 1
      # @option args [Integer] :pagesize (50) Number of assets to return per a page, default is 50, maximum is 200
      # @option args [Integer, Array<Integer>] :tags List of tag ID's to use with the tag filter on resulting assets
      # @option args [String] :orderby ('date_desc') The order to return the assets in, default is date_desc
      #   (date_desc, date_asc, title_asc, title_desc, filename_asc, filename_desc,size_asc,size_desc)
      # @option args [String] :tagfilter The tag filter conditional, "and", "or", "not"
      # @option args [String, Array<String>] :types The asset types to return, all are returned by default
      #   (video,image,document,archive,audio)
      def asset_get_by_folder_id(folder_id, args = { })
        params = {
          :folderid => folder_id
        }
        add_params = [ :page, :pagesize, :tags, :tagfilter, :orderby, :types ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.GetByFolderID', params, :primary_key_name => 'ASSETS', :paginated => true)
      end

      # Returns all assets in the project. Does not include files in sub-folders.
      #
      # @param [Integer,String] project_id The ID of the project you are requesting assets from
      # @param [Hash] args
      # @option args [Integer] :page The page of assets to return starting at 1
      # @option args [Integer] :pagesize (50) Number of assets to return per a page, default is 50, maximum is 200
      # @option args [Integer, Array<Integer>] :tags List of tag ID's to use with the tag filter on resulting assets
      # @option args [String] :orderby ('date_desc') The order to return the assets in, default is date_desc
      #   (date_desc, date_asc, title_asc, title_desc, filename_asc, filename_desc,size_asc,size_desc)
      # @option args [String] :tagfilter The tag filter conditional, "and", "or", "not"
      # @option args [String, Array<String>] :types The asset types to return, all are returned by default
      #   (video,image,document,archive,audio)
      def asset_get_by_project_id(project_id, args = { })
        params = {
          :projectid => project_id
        }
        add_params = [ { :name => :page, :default_value => 1 },
                       { :name => :pagesize, :default_value => default_page_size },
                       :tags, :tagfilter, :orderby, :types ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.GetByProjectID', params, :primary_key_name => 'ASSETS', :paginated => true)
      end

      # Returns the asset or assets that correspond to the UUID(s) passed in
      #
      # @param [String, Array<String>] asset_uuid One or a list of asset UUID's
      # @param [Hash] args
      # @option args [Integer, String, Array<Integer>, Array<String>] :tags The ID's of the tags to filter by
      # @option args [String] :orderby ('date_desc') The order to return the assets in, default is date_desc
      #   (date_desc, date_asc, title_asc, title_desc, filename_asc, filename_desc,size_asc,size_desc)
      # @option args [String] :tagfilter The tag filter conditional, "and", "or", "not"
      # @option args [Boolean] :returnonerror If TRUE then this call will return all requested assets the user has
      #   access to, striping out the ones the user does not have access to, otherwise an error would be returned
      def asset_get_by_uuid(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        add_params = [ :tags, :orderby, :tagfilter, :returnonerror ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.GetByUUID', params)
      end

      # Retrieves all the assets in a playlist
      #
      # @param [Integer] playlist_id The ID of the playlist you want the assets from
      def asset_get_by_playlist_id(playlist_id)
        params = { :playlist_id => playlist_id }
        call_method('Asset.GetByPlaylistID', params)
      end

      # Returns the processing progress as a percent value for the corresponding assets
      #
      # @param [String, Array<String>] asset_uuid The UUID's of the assets your want the progress of
      def asset_get_progress_by_uuid(asset_uuid)
        params = {
          :uuid => asset_uuid
        }
        call_method('Asset.GetProgressByUUID', params)
      end

      # Makes the corresponding assets public, allowing for direct file access with out signed URL's
      #
      # @param [String, Array<String>] asset_uuid The UUID's of the assets you want to make public
      def asset_make_public(asset_uuid)
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        call_method('Asset.MakePublic', params)
      end


      # Makes the corresponding assets secure, this prevent direct file access and forces all URL's returned by the API
      # to be signed. Secure assets required a token before the file can be accessed. Your account needs to have this
      # feature enabled. As a developer, you need to consider that changing an asset to be tokenized means it can not be
      # used externally (such as in web channels). However, secured assets can be used elsewhere in MediaSilo with no
      # limitations.
      #
      # @param [String, Array<String>] asset_uuid The UUID's of the assets you want to make secure
      def asset_make_secure(asset_uuid)
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        call_method('Asset.MakeSecure', params)
      end


      # Moves assets from one project/folder to another. Requires either a destination folderid or projectid.
      #
      # @param [String] asset_uuid The UUID's of the assets you want to move
      # @param [Hash] args
      # @option args [Integer] :projectid The ID of the project to move the assets to if you want to move them to a
      #   project
      # @option args [Integer] :folderid The ID of the folder to move the assets to if you want to move them to a folder
      def asset_move(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        add_params = [ :folderid, :projectid ]

        params = merge_additional_parameters(params, add_params, args)
        params.delete(:projectid) if params[:folderid]
        call_method('Asset.GetByFolderID', params)
      end

      # Removes tags from an asset (does not delete tags)
      #
      # @param [String] asset_uuid The UUID's of the assets you want to move
      # @param [Hash] args
      # @option args [Integer, String, Array<Integer>, Array<String>] :tagid
      # @option args [String, Array<String>] :tagname
      def asset_remove_tag(asset_uuid, args = { })
        params = {
          :uuid => asset_uuid #.is_a?(Array) ? asset_uuid.join(',') : asset_uuid
        }
        add_params = [ :tagid, :tagname ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.RemoveTag', params)
      end

      # Search filename, title, description, metadata and uploaded by username of assets based on a simple search term,
      # also returns tags used by search results
      #
      # @param [String] search_term
      # @param [Hash] args
      # @option args [Integer] :page The page of assets to return starting at 1
      # @option args [Integer] :pagesize (50) Number of assets to return per a page, default is 50, maximum is 200
      # @option args [Integer] :folderid The ID of a folder to limit the search to
      # @option args [Integer] :projectid THe ID of a project ot limit the search to
      # @option args [Integer, Array<Integer>] :tags List of tag ID's to use with the tag filter on resulting assets
      # @option args [String] :orderby ('date_desc') The order to return the assets in, default is date_desc
      #   (date_desc, date_asc, title_asc, title_desc, filename_asc, filename_desc,size_asc,size_desc)
      # @option args [String] :tagfilter The tag filter conditional, "and", "or", "not"
      # @option args [String, Array<String>] :types The asset types to return, all are returned by default
      #   (video,image,document,archive,audio)
      def asset_search(search_term, args = { })
        params = {
          :searchterm => search_term
        }
        add_params = [ { :name => :page, :default_value => 0 },
                       { :name => :pagesize, :default_value => default_page_size },
                       :folderid, :projectid, :tags, :tagfilter, :orderby, :types ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Asset.Search', params, :paginated => true, :pagination_first_page => 0)
      end

      # Tracks an "asset view" event of the currently logged in user
      #
      # @param [String] asset_uuid The UUID of the asset you want to track the user viewing
      def asset_view(asset_uuid)
        params = {
          :uuid => asset_uuid
        }
        call_method('Asset.View', params)
      end

      # Creates a new folder either in a project or in another folder
      #
      # @param [String] folder_name The name of the new folder
      # @param [Integer] project_id The ID of the project this folder belongs to
      # @param [Integer] parent_folder_id The parentid of the new folders parent, 0 if this folder is directly under a
      #   project
      def folder_create(folder_name, project_id, parent_folder_id = 0)
        params = {
          :name => folder_name,
          :projectid => project_id,
          :parentid => parent_folder_id || 0
        }
        call_method('Folder.Create', params, :primary_key_name => 'FOLDER')
      end

      # Deletes the folder of the corresponding ID
      #
      # @param [Integer] folder_id The ID of the folder you want to delete
      def folder_delete(folder_id)
        params = {
          :id => folder_id
        }
        call_method('Folder.Delete', params)
      end


      # Edits an existing folder
      #
      # @param [Integer] folder_id The ID of the folder you want to edit
      # @param [String] folder_name The name you want to change the folder's name to
      def folder_edit(folder_id, folder_name)
        params = {
          :id => folder_id,
          :name => folder_name
        }
        call_method('Folder.Edit', params)
      end

      # Returns the folder list of the next layer down form the parent ID passed in
      #
      # @param [Integer] project_id The ID of the project these folders are in
      # @param [Integer] parent_folder_id The parent ID of the current folder level, 0 for the top layer folders
      def folder_get_by_parent_id(project_id, parent_folder_id = 0)
        params = {
          :projectid => project_id,
          :parentid => (parent_folder_id || 0)
        }
        call_method('Folder.GetByParentID', params, :primary_key_name => 'FOLDERS')
      end

      # Creates metadata for the corresponding assets
      #
      # Metadata JSON object example (format must match):
      #   [{"value":"valuetest1","key":"keytest1"},{"value":"valuetest1","key":"keytest1"}]
      #
      # @param [String] asset_uuid The UUID's of the assets you want the metadata created for
      def metadata_create(asset_uuid, args = { })
        params = {
          :assetuuid => asset_uuid
        }
        add_params = [ :metadata, :key, :value, :type ]

        params = merge_additional_parameters(params, add_params, args)

        metadata = params['metadata']
        params['metadata'] = metadata_create_to_json(metadata) if metadata and !metadata.is_a?(String)

        call_method('Metadata.Create', params)
      end

      # Deletes the corresponding metadata objects
      #
      # @param [Integer, String, Array<Integer>] metadata_id The ID's of the metadata objects you want deleted
      def metadata_delete(metadata_id)
        params = {
          :id => metadata_id
        }
        call_method('Metadata.Delete', params)
      end

      # @param [Array<Hash>, String] metadata Excepts a JSON object to allow editing of multiple metadata objects at
      #   once, example:
      #   [{"id":"123","value":"valuetest1","key":"keytest1"},{"id":"123","value":"valuetest1","key":"keytest1"}]
      def metadata_edit(metadata)
        metadata = JSON.generate(metadata) if metadata.is_a?(Array)
        params = {
          :metadata => metadata
        }
        call_method('Metadata.Edit', params)
      end

      # Returns the metadata of the corresponding assets
      #
      # @param [String] asset_uuid The UUID's of the assets to return the metadata from
      # @param [Hash] args
      # @option args [String, Array<String>] :key The KEY values of specific metadata you want returned, up to 5
      # @option args [String, Array<String>] :type The types of metadata you want returned, default=all,
      #   types (custom,xmp,gps,iptc,exif)
      def metadata_get_by_asset_uuid(asset_uuid, args = { })
        params = {
          :assetuuid => asset_uuid
        }
        add_params = [ :key, :type ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Metadata.GetByAssetUUID', params)
      end

      # Creates a new project
      #
      # @param [String] project_name The name of the new project
      # @param [Hash] args
      # @option args [Integer, <Integer>, String] :userid One or more user ID's of users to have access to the
      #   project, creator is added automatically
      # @option args [String] :description The description of the new project
      def project_create(project_name, args = { })
        params = {
          :name => project_name
        }
        add_params = [ :description, :userid ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Project.Create', params, :primary_key_name => 'PROJECT')
      end

      # Deletes a project. Project must not contain sub-folders or assets. Scheduling a project for deletion regardless
      # of its content will be released in a future version.
      #
      # @param [Integer] project_id The id of the project to delete
      def project_delete(project_id)
        params = {
          :id => project_id,
        }
        call_method('Project.Delete', params)
      end

      # Edits an existing project, assigned new users to the specified project
      #
      # :name or :description is required
      #
      # @param [Integer] project_id The ID of the project you want to edit
      # @param [Hash] args
      # @option args [String] :description The description you want the projects description changed to
      # @option args [String] :name The name you want the project changed to
      def project_edit(project_id, args = { })
        params = {
          :id => project_id
        }
        add_params = [ :name, :description ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Project.Edit', params)
      end


      # Returns all projects that the current user has access to
      #
      # @param [Hash] args
      # @option args [Boolean] :adminbool (true) If the user is a "super user" (su) and this is TRUE then all projects
      #   are returned and not just the ones assigned
      # @return [Response]
      def project_get_all(args = { })
        admin_bool = args.fetch(:admin_bool, 1)
        params = {
          :adminbool => admin_bool,
        }
        call_method('Project.GetAll', params, :primary_key_name => 'PROJECTS')
      end # project_get_all

      # Creates a Quicklink for the corresponding assets
      def quicklink_create(asset_uuid, args = { })
        params = {
          :assetuuid => asset_uuid
        }
        add_params = [
          :expiration, :password, :playback, :notify, :allowdownload, :shortenurl, :private, :allowfeedback
        ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('Quicklink.Create', params)
      end

      # Edits an existing user
      #
      # @param [String] user_id
      # @param [Hash] args
      def user_edit(user_id, args = { })
        params = {
          :id => user_id
        }
        add_params = [
          :roldeid, :projectid, :company, :mobile, :phone, :country, :zip, :state, :city, :address1, :address2,
          :password, :username, :firstname, :lastname, :email, :permissions
        ]

        params = merge_additional_parameters(params, add_params, args)
        call_method('User.Edit', params)
      end

      # Authenticates and logs the corresponding user into MediaSilo, a session key is returned that can be used to
      #   retrieve other data
      #
      # @overload user_login(hostname, username, password)
      #   Executes the User.Login API command
      #   @param [String] hostname
      #   @param [String] username
      #   @param [String] password
      # @overload user_login(args)
      #   Executes the User.Login API command
      #   @param [Hash] credentials
      #   @option credentials [String] :hostname
      #   @option credentials [String] :username
      #   @option credentials [String] :password
      def user_login(*args)
        hostname, username, password = args
        if hostname.is_a?(Hash)
          credentials = normalize_hash_keys(hostname)
          hostname = credentials[:hostname]
          username = credentials[:username]
          password = credentials[:password]
        end

        params = {
          :hostname => hostname,
          :username => username,
          :password => password,

          # The apikey argument must be sent but the value is not used as this has been deprecated in the api
          :apikey   => '',
        }
        call_method('User.Login', params, :add_session_key => false)
      end

      # @!endgroup

    end

  end

end
