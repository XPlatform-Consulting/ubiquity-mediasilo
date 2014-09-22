require 'ubiquity/mediasilo/api'
require 'ubiquity/mediasilo/api/credentials'
require 'open-uri' # for download_file

class Exception
  def prefix_message(message_prefix = nil)
    begin
      raise self, "#{message_prefix ? "#{message_prefix} " : ''}#{message}", backtrace
    rescue Exception => e
      return e
    end
  end
end

module Ubiquity

  module MediaSilo

    class API

      class Utilities < MediaSilo::API

        class ExtendedResponse < Hash

          def success?
            self[:success]
          end

          def error_message
            self[:error_message]
          end

          def error_message=(v)
            self[:error_message] = v
          end

          def to_s; inspect end

        end

        DEFAULT_CASE_SENSITIVE_SEARCH = true
        DEFAULT_AUTO_RECONNECT = true
        DEFAULT_AUTO_CONNECT = true

        DEFAULT_EVENT_MATCH_REGEX = /([A-Z0-9\p{Punct}\s]*)\s([a-z\s]*)\s([A-Z0-9\p{Punct}\s]*)\s?([a-z\s]*)\s?([A-Z0-9\p{Punct}\s]*)/

        attr_accessor :logger,
                      :default_case_sensitive_search,
                      :auto_connect,
                      :auto_reconnect

        #attr_accessor :enforce_unique_project_names, :enforce_unique_folder_names

        def initialize(args = { })
          super(args)

          @default_case_sensitive_search = args.fetch(:case_sensitive_search, DEFAULT_CASE_SENSITIVE_SEARCH)

          @auto_reconnect = args.fetch(:auto_reconnect, DEFAULT_AUTO_RECONNECT)

          @auto_connect = args.fetch(:auto_connect, DEFAULT_AUTO_CONNECT)

          #@enforce_unique_project_names = args.fetch(:enforce_unique_project_names)
          #@enforce_unique_folder_names = args.fetch(:enforce_unique_folder_names)

          initialize_logger(args)
          initialize_credentials(args)
          initialize_session(credentials) if credentials and auto_connect
        end

        def initialize_logger(args = { })
          @logger = args[:logger] ||= begin
            log_to = args[:log_to] || STDERR
            _logger = Logger.new(log_to)
            log_level = args[:log_level]
            _logger.level = log_level if log_level
            _logger
          end
        end

        def initialize_credentials(args = { })
          _credentials = args[:credentials]
          @credentials = _credentials ? Credentials.new(_credentials) : _credentials
        end

        def credentials
          @credentials
        end

        # @!group OVERRIDDEN API METHODS

        # @param [string] url
        # @param [Hash] args
        # @param [Hash] options
        # @option options [Boolean] :return_extended_response (false) If true then a hash with responses for each step
        #   executed and an overall success key will be returned.
        # @return [Boolean | Hash] A boolean will be returned unless the :return_full_response options is true in which
        #   case a Hash will be returned
        def asset_create(url, args = { }, options = { })
          logger.debug "Asset Create\n\turl: #{url}\n\t\n\targs: #{args}"

          return_extended_response = options[:return_extended_response]

          utility_params = [ :title, :description, :metadata, :tags_to_add_to_asset ]
          utility_args = process_additional_parameters(utility_params, args)

          # We can't set title or description when creating the asset, so if those parameters are set then save them and then do an asset edit after asset create
          asset_modify_params = { }
          asset_modify_params['title'] = utility_args.delete('title') if utility_args['title']
          asset_modify_params['description'] = utility_args.delete('description') if utility_args['description']

          metadata = utility_args.delete('metadata') { nil }
          tags = utility_args.delete('tags_to_add_to_asset') { nil }

          _response = ExtendedResponse.new

          super(url, args)
          _response[:asset_create_response] = response.body_parsed
          _response[:asset_create_success] = success?
          unless success?
            # We received an error code from MediaSilo during the Asset.Create call so return false
            _response[:error_message] = "Error Creating Asset. #{error_message}"
            return return_extended_response ? _response : false
          end

          assets = response.body_parsed['ASSETS']
          first_asset = assets.first
          _response[:asset] = first_asset

          uuid = first_asset['uuid']
          _response[:uuid] = uuid
          unless uuid
            _response[:error_message] = "Error Getting Asset UUID from Response. #{response.body_parsed}"
            return return_extended_response ? _response : false
          end

          if not asset_modify_params.empty?
            asset_edit(uuid, asset_modify_params)
            _response[:asset_edit_response] = response.body_parsed
            _response[:asset_edit_success] = response.success?
            unless success?
              _response[:error_message] = "Error Editing Asset. #{error_message}"
              return return_extended_response ? _response : false
            end
          end

          # Since we can't set the metadata during asset_create we do it here
          if not metadata.nil? and not metadata.empty?
            metadata_create(uuid, :metadata => metadata)
            _response[:metadata_create_response] = response.body_parsed
            _response[:metadata_create_success] = success?

            unless success?
              _response[:error_message] = "Error Creating Metadata. #{error_message}"
              return return_extended_response ? _response : false
            end
          end

          if not tags.nil?
            asset_add_tag(uuid, :tagname => tags)
            _response[:tag_add_response] = response.body_parsed
            _response[:tag_add_success] = success?

            unless success?
              _response[:error_message] = "Error Adding Tag(s). #{error_message}"
              return return_extended_response ? _response : false
            end
          end

          _response[:success] = true
          return _response if return_extended_response
          return uuid
        end # asset_create

        def user_login(_credentials)
          _credentials = _credentials.to_hash if _credentials.is_a?(Credentials)
          super(_credentials)
        end

        # @!endgroup

        # @!group Convenience Methods

        # A wrapper for asset_advanced_search that builds a search_query from a search_field and a search_value
        #
        # @note Most of the fields used by asset_advanced_search are text fields on cloud search and therefore a
        #   search match will match any PART of a word. (see @refine_asset_advanced_search_by_results)
        #
        # @param [Symbol, String] search_field The field to search
        #   ["approvalstatus", "archivestatus", "averagerating", "datecreated", "datemodified", "description",
        #    "duration", "external", "filename", "height", "progress", "rating", "secure", "size", "thumbnail_large",
        #    "thumbnail_small", "title", "totalcomments", "transcriptstatus", "type", "uploaduser", "uuid", "width"]
        # @param [Symbol, String] search_value The value to search for
        # @param [String] project_id The id of the project to limit the search to.
        #   If specified this will be added to search_params
        # @param [String] folder_id The id of the folder to limit the search to.
        #   If specified this will be added to search_params
        # @param [Hash] search_query A full query to pass (search_field and search_value will be ignored)
        # @param [Hash] search_params Additional parameters to pass to asset_advanced_search
        # @param [Hash] options
        def asset_advanced_search_by_field(search_field, search_value, project_id = nil, folder_id = nil, search_query = nil, search_params = { }, options = { })
          search_params ||= options[:search_params] || { }

          # We can only search by folder id OR project id, not both
          if not(folder_id.nil? or folder_id == 0)
            search_params['folderid'] ||= folder_id
          elsif project_id
            search_params['projectid'] ||= project_id
          #else
            # Pass through the query anyway and let mediasilo return the error
          end

          #search_query = "filename|begins|#{asset_name}"
          search_query ||= %((and #{search_field}:'#{search_value}'))

          #assets = asset_search(params)
          assets = asset_advanced_search(search_query, search_params)
          assets
        end
        alias :get_asset_by :asset_advanced_search_by_field
        alias :asset_get_by :asset_advanced_search_by_field

        def asset_advanced_search_extended(search_query, args = { }, options = { })
          asset_advanced_search(search_query, args)

          # Ensure that we are working with just the assets by just using the results
          assets = response.results

          if options[:add_folder_crumbs_as_hash]
            (assets || [ ]).map! do |asset|
              add_folder_crumbs_as_hash_to_asset(asset)
            end
          end
          assets
        end

        # Refines asset_advanced_search results to exact (full string case sensitive) matches
        #
        # Most of the fields used by asset_advanced_search are text fields on cloud search and therefore a search match
        # will match any PART of a word.
        #
        # @param [String] search_value
        # @param [String] field_name The field to search.
        #   ["approvalstatus", "archivestatus", "averagerating", "datecreated", "datemodified", "description",
        #    "duration", "external", "filename", "height", "progress", "rating", "secure", "size", "thumbnail_large",
        #    "thumbnail_small", "title", "totalcomments", "transcriptstatus", "type", "uploaduser", "uuid", "width"]
        # @param [Array] assets The assets as returned by asset_adavanced_search_by_results
        # @param [Hash] options
        # @option options [Boolean] :return_first_match (false)
        # @option options [Boolean] :match_full_string (true)
        # @option options [Boolean] :case_sensitive (#default_case_sensitive_search)
        def refine_asset_advanced_search_by_field_results(field_name, search_value, assets, options)
          return unless assets
          return_first_match = options.fetch(:return_first_match, false)
          match_full_string = options.fetch(:match_full_string, true)
          case_sensitive = options.fetch(:case_sensitive, default_case_sensitive_search)
          search_value = search_value.to_s.downcase unless case_sensitive
          method = return_first_match ? :drop_while : :delete_if
          assets.send(method) do |asset|
            asset_value = case_sensitive ? asset[field_name] : asset[field_name].to_s.downcase
            nomatch = match_full_string ? (asset_value != search_value) : (!asset_value.include?(search_value))
            #logger.debug "COMPARING: '#{search_value}' #{nomatch ? '!' : '='}= '#{asset_value}'"
            nomatch
          end if assets and (match_full_string or case_sensitive)
          return assets.first if assets and return_first_match
          assets
        end

        # Add folder Crumbs as Hash fixes the issue where folders with the same name will be collapsed into a single key
        # The following fix will instead key the folder crumbs by id so that the key values will remain unique
        #
        #> JSON.parse("[{'Test':37382,'Test':73351,'Test3':73352,'Test':73353}]".gsub("'", '"'))
        #=> [{"Test"=>73353, "Test3"=>73352}]
        #
        #> JSON.parse("[{'Test':37382,'Test':73351,'Test3':73352,'Test':73353}]".gsub("'", '"').gsub(",", '},{'))
        #=> [{"Test"=>37382}, {"Test"=>73351}, {"Test3"=>73352}, {"Test"=>73353}]
        #
        #> Hash[JSON.parse("[{'Test':37382,'Test':73351,'Test3':73352,'Test':73353}]".gsub("'", '"').gsub(",", '},{')).map { |crumb|  [crumb.values.first, crumb.keys.first] }]
        #=> {37382=>"Test", 73351=>"Test", 73352=>"Test3", 73353=>"Test"}
        #
        # @param [Hash] asset Asset as returned by asset_advanced_search
        # @return [Hash] asset
        def add_folder_crumbs_as_hash_to_asset(asset)
          folder_crumbs_text = asset['searchdata']['foldercrumbs'] rescue nil
          asset['searchdata']['folder_crumbs_as_hash'] = convert_asset_advanced_search_foldercrumbs_to_hash(folder_crumbs_text)
          asset
        end

        # Converts asset advanced search foldercrumbs text into a hash keyed by id
        #
        # [{'Test':37382,'Test':73351,'Test3':73352,'Test':73353}]
        #     will be converted to
        # {37382=>"Test", 73351=>"Test", 73352=>"Test3", 73353=>"Test"}
        #
        # @param [String] folder_crumbs_text
        # @return [Hash]
        def convert_asset_advanced_search_foldercrumbs_to_hash(folder_crumbs_text)
          return unless folder_crumbs_text

          # foldercrumbs uses single quotes which won't parse, so we replace those with double quotes and replace comma's
          # with '},{' so that instead of one hash we have multiple hashes so that common keys won't collide
          folder_crumbs_as_hashes_json = folder_crumbs_text.gsub("'", '"').gsub(',', '},{')

          folder_crumbs_as_hashes = JSON.parse(folder_crumbs_as_hashes_json)

          Hash[folder_crumbs_as_hashes.map { |crumb| [crumb.values.first, crumb.keys.first] }]
        end

        # @param [Hash] args
        # @option args [String] :asset_uuid REQUIRED
        # @option args [String|Integer] :destination_project_id
        # @option args [String|Integer] :destination_folder_id
        # @option args [String] :destination_path
        # @option args [Boolean] :create_path_if_not_exist
        def asset_copy_extended(args = { })
            _response = ExtendedResponse.new

            asset_uuid = args[:asset_uuid]

            destination_folder_id = args[:destination_folder_id]
            destination_project_id = args[:destination_project_id]

            unless destination_project_id || destination_folder_id
              destination_path = args[:destination_path]
              unless destination_path
                _response[:error_message] = 'Missing required parameter. :destination_project_id, :destination_folder_id, or :destination_path is required.'
                return _response
              end

              create_path_if_not_exist = args.fetch(:create_path_if_not_exist) { args.fetch(:create_path_if_not_exists, false) }
              if create_path_if_not_exist
                create_path_result = path_create(destination_path, false)
                unless success?
                  _response[:error_message] = "Error Creating Path. #{create_path_result}"
                  return _response
                end

                destination_project_id = create_path_result[:project_id]
                destination_folder_id = create_path_result[:parent_folder_id]
              else
                check_path_result = check_path(destination_path)
                unless check_path_result[:missing_path].empty?
                  _response[:error_message] = "Path not found. '#{destination_path}' Check Path Results: #{check_path_result}"
                  return _response
                end

                existing = check_path_result[:existing]

                destination_project = existing[:project] || { }
                destination_project_id = destination_project['PROJECTID']

                destination_path_folders = existing[:folders]
                destination_folder = destination_path_folders.last || { }
                destination_folder_id = destination_folder['FOLDERID']
              end
              #destination_folder_id = nil if destination_folder_id.to_s == '0'
            end


            asset_copy_args = args
            if destination_folder_id
              asset_copy_args[:folder_id] = destination_folder_id
            elsif destination_project_id
              asset_copy_args[:project_id] = destination_project_id
            end

            create_asset_if_not_exists = args[:create_asset_if_not_exists] || args[:create_asset_if_not_exist]
            if create_asset_if_not_exists
              if create_asset_if_not_exists.is_a?(Hash)
                search_field_name = create_asset_if_not_exists[:search_field] || create_asset_if_not_exists[:search_field_name]
                search_value = create_asset_if_not_exists[:search_value]
                search_query = create_asset_if_not_exists[:search_query]
                search_args = create_asset_if_not_exists[:search_args]

                search_project_id = create_asset_if_not_exists[:search_project_id]
                search_project_id = destination_project_id if search_project_id.nil?

                search_folder_id = create_asset_if_not_exists[:search_folder_id]
                search_folder_id = destination_folder_id if search_folder_id.nil?
              else
                search_field_name = 'filename'
                source_assets = asset_get_by_uuid(asset_uuid)
                source_asset = (source_assets.is_a?(Array) ? source_assets.first : source_assets)
                unless success?
                  _response[:response] = response.body_parsed
                  _response[:error_message] = 'Error retrieving source asset filename while searching for existing asset.'
                  return _response
                end

                search_value = source_asset['filename']
                search_project_id = destination_project_id
                search_folder_id = destination_folder_id
                search_query = nil
                search_args = { }
              end
              _response[:search_field_name] = search_field_name
              _response[:search_value] = search_value
              _response[:search_project_id] = search_project_id
              _response[:search_folder_id] = search_folder_id
              _response[:search_query] = search_query
              _response[:search_params] = search_args

              get_asset_by_response = asset_get_by(search_field_name, search_value, search_project_id, search_folder_id, search_query, search_params)
              unless success?
                _response[:response] = response.body_parsed
                _response[:error_message] = 'Error searching for existing asset.'
                return _response
              end

              found_assets = get_asset_by_response['ASSETS'] if get_asset_by_response.is_a?(Hash)
              found_assets ||= [ ]
              found_asset = found_assets.first


              _response[:found_existing_asset] = !!found_asset
              destination_asset_uuid = found_asset['uuid'] if found_asset
            end

            destination_asset_uuid ||= asset_copy(asset_uuid, asset_copy_args)
            if destination_asset_uuid
              _response[:uuid] = destination_asset_uuid
              _response[:response] = response.body_parsed
            else
              _response[:response] = response.body_parsed
              _response[:error_message] = "Error copying asset.\nResponse: #{response.body_parsed}\nMS UUID: #{asset_uuid}"
              return _response
            end

            if success?
              _response[:success] = true
            else
              _response[:error_message] = 'Error Copying Asset.'
            end


            _response
          end # asset_copy

        # A version of asset_create that returns an extended response.
        #
        # @param [string] url
        # @param [Hash] args
        # @param [Hash] options
        # @option options [Boolean] :return_full_response (false) If true then a hash with responses for each step
        #   executed and an overall success key will be returned.
        # @return [Boolean | Hash] A boolean will be returned unless the :return_full_response options is true in which
        #   case a Hash will be returned
        def asset_create_extended(url, args = { }, options = { })
          return asset_create( url, args, options.merge( :return_extended_response => true ) )
          # logger.debug "Asset Create\n\turl: #{url}\n\t\n\targs: #{args}"
          #
          # utility_params = [ :title, :description, :metadata ]
          # utility_args = process_additional_parameters(utility_params, args)
          #
          # # We can't set title or description when creating the asset, so if those parameters are set then save them
          # # and then do an asset edit after asset create
          # asset_modify_params = { }
          # asset_modify_params['title'] = utility_args.delete('title') if utility_args['title']
          # asset_modify_params['description'] = utility_args.delete('description') if utility_args['description']
          #
          # metadata ||= utility_args.delete('metadata') if utility_args['metadata']
          #
          # _response = { }
          # _response[:success] = false
          #
          # asset_create(url, args)
          # _response[:asset_create_response] = response.body_parsed
          # _response[:asset_create_success] = success?
          # unless success?
          #   # We received an error code from MediaSilo during the Asset.Create call so return false
          #   _response[:error_message] = "Error Creating Asset. #{error_message}"
          #   return _response
          # end
          #
          # assets = response.body_parsed['ASSETS']
          # first_asset = assets.first
          # _response[:asset] = first_asset
          #
          # uuid = first_asset['uuid']
          # _response[:uuid] = uuid
          # unless uuid
          #   _response[:error_message] = "Error Getting Asset UUID from Response. #{response.body}"
          #   return _response
          # end
          #
          # if not asset_modify_params.empty?
          #   response = asset_edit(uuid, asset_modify_params)
          #   _response[:asset_edit_response] = response.body_parsed
          #   _response[:asset_edit_success] = response.success?
          #   unless success?
          #     _response[:error_message] = "Error Editing Asset. #{error_message}"
          #     return _response
          #   end
          # end
          #
          # # Since we can't set the metadata during asset_create we do it here
          # if not metadata.nil? and not metadata.empty?
          #   response = metadata_create(uuid, :metadata => metadata)
          #   _response[:metadata_create_response] = response.body_parsed
          #   _response[:metadata_create_success] = success?
          #   unless success?
          #     _response[:error_message] = "Error Creating Metadata. #{error_message}"
          #     return _response
          #   end
          # end
          #
          # _response[:success] = true
          # _response
        end

        # Executes an Asset.Create api call
        # Creates an asset building any missing parts of the path (Project/Folder/Asset)
        #
        # Required Parameters
        #   :file_url
        #   :file_path or :full_file_path
        #
        # Optional Parameters
        #   :metadata
        #   :overwrite_existing_asset
        def asset_create_using_path(args = { })

          file_url = args[:file_url]
          raise ArgumentError ':file_url is a required parameter.' unless file_url

          file_path = args[:file_path]
          raise ArgumentError ':file_path is a required parameter.' unless file_path

          ms_metadata = args[:metadata]

          asset_title = args[:title]
          asset_description = args[:description]
          additional_asset_create_params = { }
          additional_asset_create_params['title'] = asset_title if asset_title
          additional_asset_create_params['description'] = asset_description if asset_description

          overwrite_existing_asset = args.fetch(:overwrite_existing_asset, false)

          #logger.info { "Creating Asset on MediaSilo Using File Path: '#{file_path}'. File URL: #{file_url}" }

          #ms_uuid = ms.asset_create(file_url, { }, ms_project)

          begin
            result = path_create(file_path, true, file_url, ms_metadata, overwrite_existing_asset, additional_asset_create_params)
            # rescue => e
            #   raise e, "Exception Creating Asset Using File Path. #{e.message}", e.backtrace
          end

          output_values = { }
          output_values[:result] = result

          return false unless result and result.has_key?(:asset)
          #return publish_error('Error creating asset.') unless result and result.has_key?(:asset)

          result_asset = result[:asset]
          if result_asset == false
            ms_uuid = false
          elsif result[:asset_missing] == false
            ms_uuid = result[:existing][:asset]['uuid'] # if not result[:existing][:asset]['uuid'].nil?
          elsif result_asset.is_a?(Array)

            #Metadata creation failed but asset was created Array(false, "uuid")
            #TODO: HANDLE CASE WHERE METADATA IS NOT CREATED BUT THE ASSET IS
            ms_uuid = result_asset[1]

          else
            ms_uuid = result_asset['uuid']
            ms_uuid ||= result_asset
          end
          #Setting metadata during asset_create doesn't work so we set it here
          #response = ms.metadata_create(ms_uuid, ms_metadata) unless ms_metadata.nil?

          if ms_uuid
            output_values[:uuid] = ms_uuid
            return output_values
          else
            #return publish_error("Error creating asset.\nResponse: #{response}\nMS UUID: #{ms_uuid}\nMS Creating Missing Path Result: #{result}")
            return false
          end
        end
        alias :asset_create_using_file_path :asset_create_using_path

        # Downloads a file from a URI or file location and saves it to a local path
        #
        # @param [String] download_file_path The source path of the file being downloaded
        # @param [String] destination_file_path The destination path for the file being downloaded
        # @param [Boolean] overwrite Determines if the destination file will be overwritten if it is found to exist
        #
        # @return [Hash]
        #   * :download_file_path [String] The source path of the file being downloaded
        #   * :overwrite [Boolean] The value of the overwrite parameter when the method was called
        #   * :file_downloaded [Boolean] Indicates if the file was downloaded, will be false if overwrite was true and the file existed
        #   * :destination_file_existed [String|Boolean] The value will be 'unknown' if overwrite is true because the file exist check will not have been run inside of the method
        #   * :destination_file_path [String] The destination path for the file being downloaded
        def download_file(download_file_path, destination_file_path, overwrite = false)
          file_existed = 'unknown'
          if overwrite or not(file_existed = File.exists?(destination_file_path))
            File.open(destination_file_path, 'wb') { |tf|
              open(download_file_path) { |sf| tf.write sf.read }
            }
            file_downloaded = true
          else
            file_downloaded = false
          end
          return { :download_file_path => download_file_path, :overwrite => overwrite, :file_downloaded => file_downloaded, :destination_file_existed => file_existed, :destination_file_path => destination_file_path }
        end

        # @param [String|Hash] asset
        # @param [String] destination_file_path
        # @param [Boolean] overwrite
        # @return [Hash] see (MediaSilo#download_file)
        def asset_download_proxy_file(asset, destination_file_path, overwrite = false)
          asset = asset_get_by_uuid(asset) if asset.is_a? String
          asset = asset.first if asset.is_a?(Array)
          file_to_download = asset['fileaccess']['proxy']
          asset_download_resource(file_to_download, destination_file_path, overwrite)
        end

        # @param [String] download_file_path
        # @param [String] destination_file_path
        # @param [Boolean] overwrite
        def asset_download_resource(download_file_path, destination_file_path, overwrite = false)
          destination_file_path = File.join(destination_file_path, File.basename(URI.decode(download_file_path))) if File.directory? destination_file_path
          download_file(download_file_path, destination_file_path, overwrite)
        end

        # @param [String|Hash] asset
        # @param [String] destination_file_path
        # @param [Boolean] overwrite
        # @return [Hash] see (MediaSilo#download_file)
        def asset_download_source_file(asset, destination_file_path, overwrite = false)
          asset = asset_get_by_uuid(asset) if asset.is_a? String
          asset = asset.first if asset.is_a?(Array)
          file_to_download = asset['fileaccess']['source']
          file_to_download = URI.encode(file_to_download)
          asset_download_resource(file_to_download, destination_file_path, overwrite)
        end

        # @param [String] asset_uuid
        # @param [Hash] args A hash of arguments
        # @option args [String] :asset_uuid The uuid of the asset to edit
        # @option args [Hash] :metadata The asset's metadata.
        # @option args [Boolean] :mirror_metadata If set to true then the metadata will mirror :metadata which means that any keys existing on MediaSilo that don't exists in :metadata will be deleted from MediaSilo.
        # @option args [Array] :tags_to_add_to_asset An array of tag names to add to the asset
        # @option args [Array] :tags_to_remove_from_asset An array of tag names to remove from the asset
        # @option args [Boolean|Hash|Array] :add_quicklink_to_asset
        # @option args (see MediaSilo#asset_edit)
        def asset_edit_extended(asset_uuid, args = { }, options = { })
          if asset_uuid.is_a?(Hash)
            options = args.dup
            args = asset_uuid.dup
            asset_uuid = args.delete(:asset_uuid) { false }
            raise ArgumentError, 'Error Editing Asset. Missing required argument :asset_uuid' unless asset_uuid
          else
            args.dup
          end

          ms_metadata = args.delete(:metadata) { false }
          mirror_metadata = args.delete(:mirror_metadata) { false }

          add_tag_to_asset = args.delete(:tags_to_add) { [ ] }
          add_tag_to_asset = args.delete(:tags_to_add_to_asset) { add_tag_to_asset }

          remove_tag_from_asset = args.delete(:tags_to_remove) { [ ] }
          remove_tag_from_asset = args.delete(:tags_to_remove_from_asset) { remove_tag_from_asset }

          add_quicklink_to_asset = args.delete(:add_quicklink_to_asset) { false }

          _response = { :success => false }
          unless args.empty?
            result = asset_edit(asset_uuid, args)
            _response[:asset_edit_result] = result
            _response[:asset_edit_response] = response.body_parsed
            _response[:asset_edit_success] = success?
            unless success?
              _response[:error_message] = "Error Editing Asset. #{error_message}"
              return _response
            end

            # result = @ms.asset_edit_external(asset_uuid, args)
            # @output_values[:asset_edit_external_response] = @ms.response_body_hash
            # return publish_error("Error Editing Asset. #{@ms.error}") unless result
          end

          if ms_metadata.is_a?(Hash)
            if mirror_metadata
              result = metadata_mirror(asset_uuid, ms_metadata)
            else
              result = metadata_create_if_not_exists(asset_uuid, ms_metadata)
            end
            _response[:metadata_edit_result] = result
            _response[:metadata_edit_response] = response.body_parsed
            _response[:metadata_edit_success] = success?
            unless success?
              _response[:error_message] = "Error Editing Asset's Metadata. #{error_message}"
              return _response
            end
          end

          # TODO ADD TAG DE-DUPLICATION
          # TODO OPTIMIZE ADD/REMOVE TAG METHODS TO AGGREGATE TAGS TO MINIMUM NUMBER OF CALLS
          unless remove_tag_from_asset.nil? or remove_tag_from_asset.empty?
            [*remove_tag_from_asset].uniq.each { |tag_to_remove| tag_to_remove = { :tagname => tag_to_remove } if tag_to_remove.is_a?(String); asset_remove_tag(asset_uuid, tag_to_remove) }
          end
          unless add_tag_to_asset.nil? or add_tag_to_asset.empty?
            [*add_tag_to_asset].uniq.each { |tag_to_add| tag_to_add = { :tagname => tag_to_add } if tag_to_add.is_a?(String); asset_add_tag(asset_uuid, tag_to_add) }
          end

          if add_quicklink_to_asset
            add_quicklink_to_asset.is_a?(Hash) ? quicklink_create(asset_uuid, add_quicklink_to_asset) : quicklink_create(asset_uuid)
            _response[:quicklink_create_response] = response.body_parsed
            _response[:quicklink_create_success] = success?
            unless success?
              _response[:error_message] = "Error Adding Quicklink to Asset. #{error_message}"
              return _response
            end
          end

          _response[:success] = true
          _response
        end
        
        # Searches for assets by filename
        #
        # @param [String] asset_name The asset filename to search for
        # @param [Integer] project_id The project to limit the search to
        # @param [Integer] folder_id the folder to limit the search to
        # @param [Hash] options
        # @option options [Boolean] :return_first_match (false)
        # @option options [Boolean] :match_full_string (true)
        # @option options [Boolean] :case_sensitive (#default_case_sensitive_search)
        # @return [<Hash>, Hash, nil]
        #   If the :return_first_match option is true then a hash of the asset will be returned if a match is found.
        #   Otherwise an array of assets is returned if a match is found
        #   nil will be returned if no match was found
        def asset_get_by_filename(asset_name, project_id = nil, folder_id = nil, options = { })
          assets = asset_get_by(:filename, asset_name, project_id, folder_id, nil, { }, options)
          refine_asset_advanced_search_by_field_results('filename', asset_name, assets, options)
        end
        alias :asset_by_name :asset_get_by_filename
        alias :get_asset_by_name :asset_get_by_filename

        # Searches for assets by title
        #
        # @param [String] asset_title The asset title to search for
        # @param [Integer] project_id The project to limit the search to
        # @param [Integer] folder_id the folder to limit the search to
        # @param [Hash] options
        # @option options [Boolean] :return_first_match (false)
        # @option options [Boolean] :match_full_string (true)
        # @option options [Boolean] :case_sensitive (#default_case_sensitive_search)
        # @return [<Hash>, Hash, nil]
        #   If the :return_first_match option is true then a hash of the asset will be returned if a match is found.
        #   Otherwise an array of assets is returned if a match is found
        #   nil will be returned if no match was found
        def asset_get_by_title(asset_title, project_id = nil, folder_id = nil, options = { })
          assets = asset_get_by(:title, asset_title, project_id, folder_id, nil, { }, options)
          refine_asset_advanced_search_by_field_results('title', asset_title, assets, options)
        end
        alias :get_asset_by_title :asset_get_by_title

        # An extended version of asset_move
        # Adds the ability to move an asset using a path instead of a project/folder id
        #
        # @param [String] asset_uuid
        # @param [Hash] args
        # @option args [String, Integer] :destination_project_id
        # @option args [String, Integer] :destination_folder_id
        # @option args [String, Integer] :destination_path
        # @option args [Boolean] :create_path_if_not_exists
        def asset_move_extended(asset_uuid, args = { })
          destination_project_id = args[:destination_project_id]
          destination_folder_id = args[:destination_folder_id]

          _response = ExtendedResponse.new
          unless destination_project_id || destination_folder_id
            destination_path = args[:destination_path]
            unless destination_path
              _response[:error_message] = 'Missing required parameter. :destination_project_id, :destination_folder_id, or :destination_path is required.'
              return _response
            end

            create_path_if_not_exist = args[:create_path_if_not_exists]
            if create_path_if_not_exist
              create_path_result = path_create(destination_path, false)
              _response[:path_create_response] = create_path_result
              unless create_path_result
                _response[:error_message] = "Error Creating Path. #{create_path_result}"
                return _response
              end

              destination_project_id = create_path_result[:project_id]
              destination_folder_id = create_path_result[:parent_folder_id]
            else
              check_path_result = check_path(destination_path)
              _response[:check_path_response] = check_path_result
              unless check_path_result[:missing_path].empty?
                _response[:error_message] = "Path not found. '#{destination_path}' Check Path Results: #{check_path_result}"
                return _response
              end

              existing = check_path_result[:existing]

              destination_project = existing[:project] || { }
              destination_project_id = destination_project['PROJECTID']

              destination_path_folders = existing[:folders]
              destination_folder = destination_path_folders.last || { }
              destination_folder_id = destination_folder['FOLDERID']
            end
            #destination_folder_id = nil if destination_folder_id.to_s == '0'
          end

          args_out = {
            :projectid => destination_project_id,
            :folderid => destination_folder_id
          }
          _response[:asset_move_args] = args_out
          asset_move(asset_uuid, args_out)
          _response[:asset_move_response] = response
          unless success?
            _response[:error_message] = "Error Moving Asset. #{error_message}"
            return _response
          end
          _response[:success] = true
          _response
        end

        # Checks to see if a project/folder/asset path exists and records each as existing or missing
        #
        # @param [String] path The path to be checked for existence. Format: project[/folder][/filename]
        # @param [Boolean] path_contains_asset (false) Indicates that the path contains an asset filename
        # (@see #resolve_path)
        def check_path(path, path_contains_asset = false)
          logger.debug { "Checking Path #{path} Contains Asset: #{path_contains_asset}" }
          return false unless path

          # Remove any and all instances of '/' from the beginning of the path
          path = path[1..-1] while path.start_with? '/'

          path_ary = path.split('/')

          existing_path_result = resolve_path(path, path_contains_asset)
          existing_path_ary = existing_path_result[:id_path_ary]
          check_path_length = path_ary.length

          # Get a count of the number of elements which were found to exist
          existing_path_length = existing_path_ary.length

          # Drop the first n elements of the array which corresponds to the number of elements found to be existing
          missing_path = path_ary.drop(existing_path_length)


          # In the following logic tree the goal is indicate what was searched for and what was found. If we didn't search
          # for the component (folder/asset) then we don't want to set the missing indicator var
          # (folder_missing/asset_missing) for component as a boolean but instead leave it nil.
          missing_path_length = missing_path.length
          if missing_path_length > 0
            # something is missing

            if missing_path_length == check_path_length
              # everything is missing in our path

              project_missing = true
              if path_contains_asset
                # we are missing everything and we were looking for an asset so it must be missing
                asset_missing = true

                if check_path_length > 2
                  #if we were looking for more than two things (project, folder, and asset) and we are missing everything then folders are missing also
                  searched_folders = true
                  folder_missing = true
                else

                  #if we are only looking for 2 things then that is only project and asset, folders weren't in the path so we aren't missing them
                  searched_folders = false
                  folder_missing = false
                end
              else
                if check_path_length > 1
                  # If we are looking for more than one thing then it was project and folder and both are missing
                  searched_folders = true
                  folder_missing = true
                else
                  searched_folders = false
                  folder_missing = false
                end
              end
            else
              #we have found at least one thing and it starts with project
              project_missing = false
              if path_contains_asset
                #missing at least 1 and the asset is at the end so we know it's missing
                asset_missing = true
                if missing_path_length == 1
                  #if we are only missing one thing and it's the asset then it's not a folder!
                  folder_missing = false
                  searched_folders = check_path_length > 2
                else
                  # missing_path_length is more than 1
                  if check_path_length > 2
                    #we are looking for project, folder, and asset and missing at least 3 things so they are all missing
                    searched_folders = true
                    folder_missing = true
                  else
                    #we are only looking for project and asset so no folders are missing
                    searched_folders = false
                    folder_missing = false
                  end
                end
              else
                #if we are missing something and the project was found and there was no asset then it must be a folder
                searched_folders = true
                folder_missing = true
              end
            end
          else
            searched_folders = !existing_path_result[:folders].empty?
            project_missing = folder_missing = asset_missing = false
          end
          {
            :check_path_ary => path_ary,
            :existing => existing_path_result,
            :missing_path => missing_path,
            :searched_folders => searched_folders,
            :project_missing => project_missing,
            :folder_missing => folder_missing,
            :asset_missing => asset_missing,
          }
        end

        def folder_by_name(project_id, folder_name, parent_id, options = { })
          case_sensitive = options.fetch(:case_sensitive, default_case_sensitive_search)
          return_all_matches = !options.fetch(:return_first_match, false)

          folders = options[:folders] || folder_get_by_parent_id(project_id, parent_id)
          return false unless folders

          folder_name.upcase! unless case_sensitive

          # Use delete_if instead of keep_if to be ruby 1.8 compatible
          folders.dup.delete_if do |folder|
            folder_name_to_test = folder['NAME']
            folder_name_to_test.upcase! unless case_sensitive
            no_match = (folder_name_to_test != folder_name)
            return folder unless no_match or return_all_matches
            no_match
          end
          return nil unless return_all_matches
          folders
        end
        alias :get_folder_by_name :folder_by_name

        def project_by_name(project_name, options = { })
          case_sensitive = options.fetch(:case_sensitive, default_case_sensitive_search)
          return_all_matches = !options.fetch(:return_first_match, false)

          projects = options[:projects] || project_get_all
          return false unless projects

          project_name.upcase! unless case_sensitive

          # Use delete_if instead of keep_if to be ruby 1.8 compatible
          projects = projects.dup.delete_if do |project|
            project_name_to_test = project['NAME']
            project_name_to_test.upcase! unless case_sensitive
            no_match = (project_name_to_test != project_name)
            return project unless no_match or return_all_matches
            no_match
          end
          return nil unless return_all_matches
          projects
        end
        alias :get_project_by_name :project_by_name

        # A metadata creation utility method that checks for existing keys to avoid duplication
        #
        # @param [String] asset_uuid
        # @param [Hash] metadata
        # @return [Boolean]
        def metadata_create_if_not_exists(asset_uuid, metadata)
          return asset_uuid.map { |au| metadata_create_if_not_exists(au, metadata) } if asset_uuid.is_a?(Array)
          return unless metadata.is_a?(Hash) and !metadata.empty?

          md_existing = metadata_get_by_asset_uuid(asset_uuid)
          md_existing_keys = {}
          md_existing.each do |ms_md|
            md_existing_keys[ms_md['key']] = ms_md
          end if md_existing.is_a?(Array)

          md_to_create = { }
          md_to_edit = [ ]

          metadata.each do |key, value|
            if md_existing_keys.has_key?(key)
              md_current = md_existing_keys[key]
              md_to_edit << { 'id' => md_current['id'], 'value' => value, 'key' => key } unless (md_current['value'] == value)
            else
              md_to_create[key] = value
            end
          end
          result_create = md_to_create.empty? || metadata_create(asset_uuid, md_to_create)
          result_edit   = md_to_edit.empty?   || metadata_edit(asset_uuid, JSON.generate(md_to_edit))

          return (result_create and result_edit)
        end

        # A method that mirrors the metadata passed to the asset, deleting any keys that don't exist in the metadata param
        #
        # @param [String] asset_uuid
        # @param [Hash] metadata
        def metadata_mirror(asset_uuid, metadata = { })
          return asset_uuid.map { |au| metadata_mirror(au, metadata) } if asset_uuid.is_a?(Array)

          md_to_delete = [ ]
          md_existing_keys = { }

          md_existing = metadata_get_by_asset_uuid(asset_uuid)
          md_existing.each do |ms_md|
            ms_md_key = ms_md['key']
            ms_md_id = ms_md['id']
            if metadata.key?(ms_md_key)
              md_existing_keys[ms_md_key] = ms_md
            else
              md_to_delete << ms_md_id
            end
          end

          md_to_create = { }
          md_to_edit = [ ]

          metadata.each do |key, value|
            if md_existing_keys.has_key?(key)
              md_current = md_existing_keys[key]
              md_to_edit << { 'id' => md_current['id'], 'value' => value, 'key' => key } unless (md_current['value'] == value)
            else
              md_to_create[key] = value
            end
          end
          result_delete = true
          result_create = true
          result_edit = true

          result_delete = metadata_delete(md_to_delete) unless md_to_delete.empty?
          result_create = metadata_create(asset_uuid, md_to_create) unless md_to_create.empty?
          result_edit = metadata_edit(asset_uuid, JSON.generate(md_to_edit)) unless md_to_edit.empty?

          return (result_delete and result_create and result_edit)
        end # metadata_mirror

        # Transforms a metadata hash from MediaSilo to a simple key value hash and discards everything else
        #
        # @param [Hash] metadata_from_ms The asset's metadata as it comes from MediaSilo
        # @return [Hash] Returns a transformed hash consisting only of key => value pairs
        def metadata_transform_hash(metadata_from_ms)
          Hash[ metadata_from_ms.map { |cm| [ cm['key'], cm['value'] ] } ]
        end # metadata_transform_hash

        # Takes a file system type path and resolves the MediaSilo id's for each of the folders of that path
        #
        # @param [Integer] project_id The id of the project the folder resides in
        # @param [String] path A directory path separated by / of folders to traverse
        # @param [Integer] parent_id The ID of the parent folder to begin the search in
        def resolve_folder_path(project_id, path, parent_id = 0)
          if path.is_a?(Array)
            path_ary = path.dup
          elsif path.is_a? String
            path = [1..-1] while path.start_with?('/')
            path_ary = path.split('/')
          end

          return nil if !path_ary or path_ary.empty?

          id_path_ary = [ ]
          name_path_ary = [ ]

          folder_name = path_ary.shift
          name_path_ary << folder_name

          folder = get_folder_by_name(project_id, folder_name, parent_id, :return_first_match => true)
          return nil unless folder

          folder_ary = [ folder ]

          folder_id = folder['FOLDERID']

          id_path_ary << folder_id.to_s

          resolved_folder_path = resolve_folder_path(project_id, path_ary, folder_id)

          unless resolved_folder_path.nil?
            id_path_ary.concat(resolved_folder_path[:id_path_ary] || [ ])
            name_path_ary.concat(resolved_folder_path[:name_path_ary] || [ ])
            folder_ary.concat(resolved_folder_path[:folder_ary] || [ ])
          end

          return {
            :id_path_ary => id_path_ary,
            :name_path_ary => name_path_ary,
            :folders_ary => folder_ary
          }
        end

        # Takes a file system type path and resolves the MediaSilo id's for each of the elements of that path which exist
        #
        # The method check_path uses this method to determine what part of a path does or doesn't exist
        #
        # @param [String] path The path of the asset on MediaSilo {project_name}/{folder_name} or
        #   {project_name}/{folder_name}/{asset_name}
        # @param [Boolean] path_contains_asset True indicates that the path ends with the asset name as opposed to a
        #   folder name
        # @param [Hash] options
        # @option options [String] :asset_name_field Valid values are: :title, :filename, or :description
        # @return [Hash]
        #   * :name_path [String]
        #   * :id_path [String]
        #   * :name_path_ary [Array]
        #   * :id_path_ary [Array]
        #   * :project [nil|false|Hash]
        #   * :asset [nil|Hash]
        def resolve_path(path, path_contains_asset = false, options = { })
          logger.debug { "Resolving Path: '#{path}' Path Contains Asset: #{path_contains_asset} Options: #{options}" }

          return_first_matching_asset = options.fetch(:return_first_matching_asset, true)

          id_path_ary = [ ]
          name_path_ary = [ ]

          if path.is_a?(String)
            # Remove any leading slashes
            path = path[1..-1] while path.start_with?('/')

            path_ary = path.split('/')
          elsif path.is_a?(Array)
            path_ary = path.dup
          else
            raise ArgumentError, "path is required to be a String or an Array. Path Class Name: #{path.class.name}"
          end

          asset_name = path_ary.pop if path_contains_asset

          # The first element must be the name of the project
          project_name = path_ary.shift
          raise ArgumentError, 'path must contain a project name.' unless project_name

          project = get_project_by_name(project_name, :return_first_match => true)
          return {
            :name_path => '/',
            :name_path_ary => path_ary,

            :id_path => '/',
            :id_path_ary => [ ],

            :project => project,
            :asset => nil,
            :folders => [ ]
          } if !project or project.empty?

          project_id = project['PROJECTID']
          id_path_ary << project_id
          name_path_ary << project_name

          parsed_folders = resolve_folder_path(project_id, path_ary)
          if not parsed_folders.nil?
            id_path_ary.concat(parsed_folders[:id_path_ary])
            name_path_ary.concat(parsed_folders[:name_path_ary])
            asset_folder_id = parsed_folders[:id_path_ary].last if path_contains_asset
            folders = parsed_folders.fetch(:folder_ary, [ ])

            if path_contains_asset
              # The name of the attribute to search the asset name for (Valid options are :title or :filename)
              asset_name_field = options[:asset_name_field] || :filename
              case asset_name_field.to_s.downcase.to_sym
                when :filename
                  asset = asset_get_by_filename(asset_name, project_id, asset_folder_id, :return_first_match => return_first_matching_asset)
                when :title
                  asset = asset_get_by_title(asset_name, project_id, asset_folder_id, :return_first_match => return_first_matching_asset)
                else
                  raise ArgumentError, ":asset_name_field value is not a valid option. It must be :title or :filename. Current value: #{asset_name_field}"
              end
            end
            if asset
              if asset.is_a?(Array)
                # Just add the whole array to the array
                id_path_ary << asset.map { |_asset| _asset['uuid'] }
                name_path_ary << asset.map { |_asset| _asset['filename'] }
              else
                id_path_ary << asset['uuid']
                name_path_ary << File.basename(asset['filename'])
              end
            else
              asset = nil
            end
          else
            asset = nil
            folders = [ ]
          end


          return {
            :name_path => "/#{name_path_ary.join('/')}",
            :name_path_ary => name_path_ary,

            :id_path => "/#{id_path_ary.join('/')}",
            :id_path_ary => id_path_ary,

            :project => project,
            :asset => asset,
            :folders => folders
          }
        end

        # Calls check_path to see if any part of a project/folder/asset path are missing from MediaSilo and creates any part that is missing
        #
        # @param [String] path The path to create inside of MediaSilo
        # @param [Boolean] contains_asset see #path_resolve
        # @param [String|nil] asset_url
        # @param [Hash|nil] metadata
        # @param [Boolean] overwrite_asset Will cause the asset to be deleted and recreated
        # @return [Hash]
        #  {
        #    :check_path_ary=>["create_missing_path_test"],
        #    :existing=>{
        #        :name_path=>"/",
        #        :id_path=>"/",
        #        :name_path_ary=>[],
        #        :id_path_ary=>[],
        #        :project=>false,
        #        :asset=>nil,
        #        :folders=>[]
        #    },
        #    :missing_path=>[],
        #    :searched_folders=>false,
        #    :project_missing=>true,
        #    :folder_missing=>false,
        #    :asset_missing=>nil,
        #    :project=>{
        #        "id"=>30620,
        #        "datecreated"=>"June, 05 2013 15:20:15",
        #        "description"=>"",
        #        "uuid"=>"15C84A5F-B2D9-0E2F-507D94189F8A1FDC",
        #        "name"=>"create_missing_path_test"
        #    },
        #    :project_id=>30620,
        #    :parent_folder_id=>0
        #  }
        def path_create(path, contains_asset = false, asset_url = nil, metadata = nil, overwrite_asset = false, additional_asset_create_params = { })
          cp_result = check_path(path, contains_asset)
          logger.debug { "CHECK PATH RESULT #{cp_result.inspect}" }
          return false unless cp_result

          project_missing = cp_result[:project_missing]
          folder_missing = cp_result[:folder_missing]
          asset_missing   = cp_result[:asset_missing]

          asset = cp_result[:existing][:asset]

          unless project_missing or folder_missing or asset_missing or (!asset_missing and overwrite_asset)
            project_id = cp_result[:existing][:id_path_ary].first
            asset = cp_result[:existing][:asset]
            if contains_asset
              asset_id = cp_result[:existing][:id_path_ary].last
              parent_folder_id = cp_result[:existing][:id_path_ary].fetch(-2)
            else
              asset_id = nil
              parent_folder_id = cp_result[:existing][:id_path_ary].last
            end

            result = cp_result.merge({ :project_id => project_id, :parent_folder_id => parent_folder_id, :asset_id => asset_id, :asset => asset })
            logger.debug { "Create Missing Path Result: #{result.inspect}" }
            return result
          end
          searched_folders = cp_result[:searched_folders]

          missing_path = cp_result[:missing_path]

          project_name = cp_result[:check_path_ary][0]
          #logger.debug "PMP: #{missing_path}"
          if project_missing
            logger.debug { "Missing Project - Creating Project #{project_name}" }
            project = project_create(project_name)
            cp_result[:project] = project

            project_id = project['id']
            missing_path.shift
            logger.debug { "Created Project #{project_name} - #{project_id}" }
          else
            project_id = cp_result[:existing][:id_path_ary][0]
          end

          if searched_folders
            if folder_missing
              # logger.debug "FMP: #{missing_path}"

              parent_folder_id = cp_result[:existing][:id_path_ary].last unless cp_result[:existing][:id_path_ary].empty? or cp_result[:existing][:id_path_ary].length == 1
              parent_folder_id ||= 0

              asset_name = missing_path.pop if contains_asset

              missing_path.each { |folder_name|
                begin
                  logger.debug { "Creating folder #{folder_name} parent id: #{parent_folder_id} project id: #{project_id}" }
                  new_folder = folder_create(folder_name, project_id, parent_folder_id)
                  logger.debug { "New Folder: #{new_folder.inspect}" }
                  parent_folder_id = new_folder['id']
                  logger.debug { "Folder Created #{new_folder} - #{parent_folder_id}" }
                rescue => e
                  raise e.prefix_message("Failed to create folder '#{folder_name}' parent id: '#{parent_folder_id}' project id: '#{project_id}'. Exception:")
                end
              }

              missing_path = asset_name
            else
              if contains_asset and not asset_missing
                parent_folder_id = cp_result[:existing][:id_path_ary].fetch(-2)
              else
                parent_folder_id = cp_result[:existing][:id_path_ary].last
              end
            end
          else
            parent_folder_id = 0
          end

          if contains_asset
            additional_asset_create_params = { } unless additional_asset_create_params.is_a?(Hash)
            additional_asset_create_params['folderid'] = parent_folder_id
            additional_asset_create_params['projectid'] = project_id
            additional_asset_create_params[:metadata] = metadata

            if asset_missing
              asset = asset_create(asset_url, additional_asset_create_params)
            elsif overwrite_asset
              asset_uuid = cp_result[:existing][:id_path_ary].last
              begin
                raise "Error Message: #{error_message}" unless asset_delete(asset_uuid)
              rescue => e
                raise e.prefix_message("Error Deleting Existing Asset. Asset UUID: #{asset_uuid} Exception:")
              end

              asset = asset_create(asset_url, additional_asset_create_params)
            else
              additional_asset_create_params = additional_asset_create_params.delete_if { |k,v| asset[k] == v }
              asset_edit_extended(asset['uuid'], additional_asset_create_params) unless additional_asset_create_params.empty?
            end
            cp_result[:asset] = asset
          end
          result = cp_result.merge({ :project_id => project_id, :parent_folder_id => parent_folder_id })
          logger.debug { "Create Missing Path Result: #{result.inspect}" }
          return result
        end 
        alias :create_path :path_create

        # Deletes a named path
        #
        # Since MediaSilo does not allow you to delete non empty projects or directories this method will traverse
        # either an entire project and/or a folder and delete the contents
        #
        # @param [String] path The path that you wish to delete. If the path ends with '*' then only the contents of
        #   the parent will be deleted and not the parent itself.
        # @param [Hash] options
        # @option options [Boolean] recursive (false) Tells the method to recurse into any sub-folders. Usually you
        #   would want this to be true, but the default requires you to be explicit about wanting to delete sub-folders
        #   so the default is false.
        # @option options [Boolean] include_assets (false) Tells the method to delete any assets in any directory that
        #   it traverses into. Usually you would want this to be true, but the default requires you to be explicit
        #   about wanting to delete assets so the default is false
        # @option options [Boolean] :delete_contents_only Tells the method to not delete the parent object
        #   (project or folder) unless this is set to true. This option value will be overridden and set to true if the
        #   path ends with an asterisk (e.g. /project/folder/*)
        # @option options [Boolean] :raise_exception_on_error (false) Determines if false will be returned on error or
        #   if an exception will be raised
        # @option option [Boolean] :dry_run (false) Will log the operations to the debug log but will not attempt to
        #   execute the MediaSilo api commands
        def path_delete(path, options = { })
          raise_exception_on_error = options.fetch(:raise_exception_on_error, true)
          recursive = (options.fetch(:recursive, false) === true) ? true : false
          include_assets = (options.fetch(:include_assets, false) === true) ? true : false

          path = path[1..-1] if path.start_with? '/' # Remove the leading slash if it is present
          path_ary = path.split('/') # Turn the path into an array of names

          raise ArgumentError, 'Path is empty. Nothing to do.' if path_ary.empty?

          if path_ary.last == '*'
            path_ary.pop

            if path_ary.empty?
              delete_all_projects = options.fetch(:delete_all_projects)
              raise ArgumentError, 'Wildcard Project Deletion is not Enabled.' unless delete_all_projects

              admin_bool = options.fetch(:admin_bool, false)

              projects = project_get_all(:admin_bool => admin_bool)
              return projects.map { |project| path_delete(project['NAME'], options)}
            end

            delete_contents_only = true
          else
            delete_contents_only = options.fetch(:delete_contents_only, false)
          end

          result = check_path(path_ary.join('/'))
          raise "Error checking path. '#{error_message}'" unless result

          existing_path = result[:existing][:id_path_ary]
          missing_path = result[:missing_path]

          #The path was not found
          raise "Path not found. Path: '#{path}'" unless missing_path.empty?

          id_path_ary = existing_path

          project_id = id_path_ary.shift # Pull the project_id out of the beginning of the array

          if id_path_ary.empty?
            folder_id = 0
          else
            folder_id = id_path_ary.last
          end

          path_delete_by_id(project_id, folder_id, recursive, include_assets, delete_contents_only, options)
        rescue ArgumentError, RuntimeError => e
          raise e if raise_exception_on_error
          return false
        end

        # Deletes a project's and/or folder's contents.
        #
        # @param [String|Integer] project_id The id of the project that you wish to delete.
        # @param [String|Integer] folder_id (0) The parent_folder in the project that you would want to delete the
        #   contents of. Defaults to 0 which is the root folder of the project.
        # @param [Boolean] recursive (false) Tells the method to recurse into any sub-folders. Usually you would want
        #   this to be true, but the default requires you to be explicit about wanting to delete sub-folders so the
        #   default is false.
        # @param [Boolean] include_assets (false) Tells the method to delete any assets in any directory that it
        #   traverses into. Usually you would want this to be true, but the default requires you to be explicit about
        #   wanting to delete assets so the default is false
        # @param [Boolean] delete_contents_only (true) Tells the method to not delete the parent object
        #   (project or folder) unless this is set to true.
        # @param [Hash] options
        # @option option [Boolean] :dry_run
        # @option option [Boolean] :delete_assets_only Will only delete assets along the path but will leave the project
        #   and folders in place
        def path_delete_by_id(project_id, folder_id = 0, recursive = false, include_assets = false, delete_contents_only = true, options = { })
          dry_run = options.fetch(:dry_run, false)
          delete_assets_only = options.fetch(:delete_assets_only, false)

          raise ArgumentError, 'include_assets must be true to use the delete_assets_only option.' if delete_assets_only and !include_assets

          @logger.debug { "Deleting Path By ID - Project ID: #{project_id} Folder ID: #{folder_id} Recursive: #{recursive} Include Assets: #{include_assets} Delete Contents Only: #{delete_contents_only} Options: #{options.inspect}" }

          folders = folder_get_by_parent_id(project_id, folder_id ||= 0) || [ ]
          if recursive
            total_folders = folders.length
            folder_counter = 0
            folders.delete_if do |folder|
              folder_counter += 1

              @logger.debug { "Deleting Contents of Folder #{folder_counter} of #{total_folders} - #{folder}" }

              # Pass delete_assets_only as the delete_contents_only. This way if we aren't deleting assets only then
              # sub-folders and assets will get deleted recursively, otherwise only assets will be deleted
              path_delete_by_id(project_id, folder['FOLDERID'], recursive, include_assets, delete_assets_only, options)
            end
          end


          if include_assets
            if folder_id == 0
              assets = asset_get_by_project_id(project_id)
            else
              assets = asset_get_by_folder_id(folder_id)
            end

            total_assets = assets.length
            asset_counter = 0
            assets.delete_if { |asset|
              asset_counter += 1
              @logger.debug { "Deleting Asset #{asset_counter} of #{total_assets} - #{asset}" }
              dry_run ? true : asset_delete(asset['uuid'])
            }
          else
            assets = [ ] # make assets.empty? pass later on. let ms throw an error if the project/folder isn't empty
          end

          unless delete_contents_only or delete_assets_only
            if folders.empty? and assets.empty?
              if folder_id === 0
                @logger.debug { "Deleting Project #{project_id}" }
                return ( dry_run ? true : project_delete(project_id) )
              else
                @logger.debug { "Deleting Folder #{folder_id}" }
                return ( dry_run ? true : folder_delete(folder_id) )
              end
            else
              return true if dry_run
              warn "Assets remaining in project/folder: #{project_id}/#{folder_id} : Assets: #{assets.inspect}" unless assets.empty?
              warn "Folders remaining in project/folder: #{project_id}/#{folder_id} : Folders: #{folders.inspect}" unless folders.empty?
              return false
            end
          end

          return true
        end

        # # @param [String] source_string
        # # @param [String] search_for_string
        # # @param [Symbol] method Any string method that will take a string as an argument. Ex: :eql?, :start_with?, :end_with?
        # def compare_strings(source_string, search_for_string, method = :eql?); return source_string.send(method, search_for_string); end # compare_strings

        # Searches asset events for event(s) meeting the search criteria
        #
        # @param [String] asset_uuid
        # @param [Hash] search_criteria
        # @option search_criteria [String] :event_code
        # @option search_criteria [Hash] :description

        # @param [Symbol|Integer|String] occurrence_to_search_for The results are in a stack from newest to oldest, so first matches the newest record and last matches the oldest record
        # @option occurrence_to_search_for [Symbol|String] :all
        # @option occurrence_to_search_for [SymbolString] :first Return the most recent record found
        # @option occurrence_to_search_for [Symbol|String] :last Return the oldest record found
        #
        # @param [Hash] options
        # @option options [Boolean] :include_event_detail (false)
        # @option options [Boolean] :include_event_user (false)
        #
        #
        # QUICKLINK_CREATE_VIDEO
        # TAG_ADD_TO_VIDEO
        # TAG_REMOVE_FROM_VIDEO
        # VIDEO_DOWNLOAD
        # VIDEO_VIEW
        # VIDEO_UPLOAD_FTP
        #
        def search_asset_events(asset_uuid, search_criteria = { }, occurrence_to_search_for = :all, options = { })
          return asset_uuid.collect { |cau| search_asset_events(cau, search_criteria, occurrence_to_search_for, options) } if asset_uuid.is_a?(Array)
          options[:asset_uuid] = asset_uuid
          return search_events(search_criteria, occurrence_to_search_for, options)
        end # search_asset_events

        def search_events(search_criteria = { }, occurrence_to_search_for = :all, options = { })

          args_out = {
            :search_criteria => search_criteria,
            :occurrence_to_search_for => occurrence_to_search_for,
            :options => options
          }

          events = EventSearch.new(args_out)

          include_event_detail = options.fetch(:include_event_detail, false)
          include_event_user = options.fetch(:include_event_user, false)

          user_cache = { }
          events.map do |event|
            if include_event_detail
              event_uuid = event['uuid']
              event['detail'] = event_get_detail(event_uuid) if event_uuid
            end

            if include_event_user
              user_id = event['userid']
              if user_id
                user = user_cache[user_id] ||= user_get_by_id(user_id)
                event['user'] = user # if user
              end
            end

            event
          end

          return events

          # events = options.fetch(:events, false)
          #
          # asset_uuid = options.fetch(:asset_uuid, false)
          # events ||= event_get_by_asset_uuid(asset_uuid) if asset_uuid
          # events ||= event_get_all
          # events ||= [ ]
          #
          # # Events are in an array(stack) going from newest to oldest
          # if occurrence_to_search_for.is_a?(Symbol) || occurrence_to_search_for.is_a?(String)
          #   case occurrence_to_search_for.downcase.to_sym
          #     when :first, :newest
          #       occurrence_to_search_for = 1
          #     when :last, :oldest
          #       occurrence_to_search_for = -1
          #     when :all
          #       occurrence_to_search_for = nil
          #   end
          # else
          #   occurrence_to_search_for = 1 if occurrence_to_search_for == 0
          # end
          #
          # #if search_criteria.empty? or events.empty?
          # #  return events.first if occurrence_to_search_for == 1
          # #  return events.last  if occurrence_to_search_for == -1
          # #  return events if occurrence_to_search_for == -2
          # #end
          #
          # event_code_to_search_for = search_criteria.fetch(:event_code, false)
          # event_code_to_search_for.upcase! if event_code_to_search_for.is_a?(String)
          # event_code_search_method = options.fetch(:event_code_search_method, :eql?)
          #
          # time_to_search_for = search_criteria.fetch(:time, false)
          # case time_to_search_for
          #   when false
          #     #
          #   else
          #     time_start = time_stop = time_to_search_for
          # end
          #
          # description_search = search_criteria.fetch(:description, false)
          # description_search = false if description_search.respond_to?(:empty?) and description_search.empty?
          #
          # if description_search
          #   username_to_search_for ||= description_search.fetch(:username, false)
          #   username_to_search_for.upcase! if username_to_search_for
          #   username_search_method = options.fetch(:username_search_method, :eql?)
          #
          #   action_to_search_for ||= description_search.fetch(:action, false)
          #   action_to_search_for.downcase! if action_to_search_for
          #   action_search_method = options.fetch(:action_search_method, :eql?)
          #
          #   object1_to_search_for ||= description_search.fetch(:tag,
          #                                                      description_search.fetch(:filename,
          #                                                                               description_search.fetch(:object1, false)))
          #   object1_to_search_for.upcase! if object1_to_search_for
          #   object1_search_method = options.fetch(:object1_search_method, :eql?)
          #
          #   object2_to_search_for ||= description_search.fetch(:filename,
          #                                                      description_search.fetch(:object2, false))
          #   object2_to_search_for.upcase! if object2_to_search_for
          #   object2_search_method = options.fetch(:object2_search_method, :eql?)
          # end
          #
          # include_event_detail = options.fetch(:include_event_detail, false)
          # include_event_user = options.fetch(:include_event_user, false)
          # user_cache = { }
          #
          # found_events = [ ]
          # current_occurrence = 0
          # occurrence_found = false
          # events.each { |event|
          #   event_code = event['code']
          #   logger.debug { "No code match: #{event_code} !#{event_code_search_method} #{event_code_to_search_for}" } and next unless compare_strings(event_code, event_code_to_search_for, event_code_search_method) if event_code_to_search_for
          #   logger.debug { "Code match: #{event_code} #{event_code_search_method} #{event_code_to_search_for}" }
          #
          #   if time_to_search_for
          #     event_time = event['timestamp']
          #     next unless event_time >= time_start and event_time <= time_stop
          #   end
          #
          #
          #   if description_search
          #     case event_code
          #       when 'PRESENTATION_VIEWED'
          #         # "Presentation THE SOMETHING COLLECTION 2013 - 2014 was viewed"
          #         regex = false
          #       when 'PRESENTATION_VIDEO_VIEWED'
          #         # "LSGA779L-1 A PYTHAGOREAN THEORIES ON SCREENER.MOV was viewed in presentation THE SOMETHING COLLECTION 2013 - 2014"
          #         regex = false
          #       when 'QUICKLINK_VIEW_EMAIL'
          #         # "user@domain.com viewed 726358-006_DOUG OBERHELMAN CATERPILLER_1.MOV via QuickLink"
          #         regex = false
          #       else
          #         regex = DEFAULT_EVENT_MATCH_REGEX
          #     end
          #     if regex
          #       match = regex.match(event.fetch('description', '')).to_a
          #       @logger.debug { "Parsed Event Description: #{match.inspect}" }
          #       if match
          #         #description_hash = /(?<username>\w*)\s{1}(?<action>[a-z\s]*)\s{1}(?<object1>[A-Z0-9\p{Punct}\s]*)\s?(?<preposition>[a-z\s]*)\s?(?<object2>[A-Z0-9\p{Punct}\s]*)/.match(event.fetch('description', ''))
          #         username, action, object1, preposition, object2 = match.to_a
          #         #next unless description_hash['username'] == username_to_search_for if username_to_search_for
          #         #next unless description_hash['action'] == action_to_search_for     if action_to_search_for
          #         #next unless description_hash['object1'].strip == object1_to_search_for   if object1_to_search_for
          #         #next unless description_hash['object2'] == object2_to_search_for if object2_to_search_for
          #
          #         next unless compare_strings(username, username_to_search_for, username_search_method) if username_to_search_for
          #         next unless compare_strings(action, action_to_search_for, action_search_method)     if action_to_search_for
          #         next unless compare_strings(object1.strip, object1_to_search_for, object1_search_method)   if object1_to_search_for
          #         next unless compare_strings(object2, object2_to_search_for, object2_search_method) if object2_to_search_for
          #       end
          #     end
          #   end
          #
          #   if include_event_detail
          #     event_uuid = event['uuid']
          #     event['detail'] = event_get_detail(event_uuid) if event_uuid
          #   end
          #
          #   if include_event_user
          #     user_id = event['userid']
          #     if user_id
          #       user = user_cache[user_id] ||= user_get_by_id(user_id)
          #       event['user'] = user # if user
          #     end
          #   end
          #
          #   current_occurrence += 1
          #   found_events << event
          #
          #   (occurrence_found = true) and break if occurrence_to_search_for and (current_occurrence == occurrence_to_search_for)
          #
          # }
          # return false if found_events.empty?
          # if occurrence_to_search_for.is_a?(Integer)
          #   return found_events.last if occurrence_found or (occurrence_to_search_for == -1)
          #   return found_events[occurrence_to_search_for] # Could be negative
          # end
          # return found_events
        end # search_events

        # @!endgroup
      end

    end

  end

end

class EventSearch

  attr_accessor :logger

  attr_accessor :found_events,
                :current_occurrence,
                :user_cache,

                # Parameters set by arguments
                :include_event_detail,
                :include_event_user,

                :events,
                :search_criteria,
                :occurrence_to_search_for,

                :event_code_to_search_for,
                :event_code_search_method,

                :description_to_search_for,

                :username_to_search_for,
                :username_search_method,

                :action_to_search_for,
                :action_search_method,

                :object1_to_search_for,
                :object1_search_method,

                :object2_to_search_for,
                :object2_search_method,

                :time_to_search_for,
                :time_start,
                :time_end

  def initialize(args = { })
    initialize_logger(args)

    @found_events = [ ]
    @current_occurrence = 0
    @user_cache = { }

    @events = args[:events]
    raise ArgumentError, ':events is a required argument.' unless events

    @search_criteria = args[:search_critera]
    raise ArgumentError, ':search_criteria is a required argument.' unless search_criteria

    process_search_criteria
    initialize_occurrence_to_search_for(args)
    initialize_time_to_search_for(args)
  end

  def initialize_time_to_search_for(args = { })
    @time_to_search_for = search_criteria.fetch(:time, false)
    case time_to_search_for
      when false
        #
      else
        @time_start = @time_end = time_to_search_for
    end

  end

  def initialize_logger(args = { })
    @logger = args[:logger] || Logger.new(args[:log_to] || STDOUT)
  end

  def initialize_occurrence_to_search_for(args = { })
    @occurrence_to_search_for = args[:occurrence_to_search_for]
    if occurrence_to_search_for.is_a?(Symbol) || occurrence_to_search_for.is_a?(String)
      case occurrence_to_search_for.downcase.to_sym
        when :first, :newest
          @occurrence_to_search_for = 1
        when :last, :oldest
          @occurrence_to_search_for = -1
        when :all
          @occurrence_to_search_for = nil
      end
    else
      @occurrence_to_search_for = 1 if occurrence_to_search_for == 0
    end

  end



  def process_search_criteria(search_criteria = @search_criteria)
    @event_code_to_search_for = search_criteria.fetch(:event_code, false)
    @event_code_to_search_for.upcase! if event_code_to_search_for.is_a?(String)
    @event_code_search_method = options.fetch(:event_code_search_method, :eql?)

    # time_to_search_for = search_criteria.fetch(:time, false)
    # case time_to_search_for
    #   when false
    #     #
    #   else
    #     time_start = time_stop = time_to_search_for
    # end

    @description_to_search_for = search_criteria.fetch(:description, false)
    @description_to_search_for = false if description_to_search_for.respond_to?(:empty?) and description_to_search_for.empty?

    if description_to_search_for.is_a?(Hash)
      @username_to_search_for ||= description_to_search_for.fetch(:username, false)
      @username_to_search_for.upcase! if username_to_search_for
      @username_search_method = options.fetch(:username_search_method, :eql?)

      @action_to_search_for ||= description_to_search_for.fetch(:action, false)
      @action_to_search_for.downcase! if action_to_search_for
      @action_search_method = options.fetch(:action_search_method, :eql?)

      @object1_to_search_for ||= description_to_search_for.fetch(:tag) do
        description_to_search_for.fetch(:filename) do
          description_to_search_for.fetch(:object1, false)
        end
      end


      @object1_to_search_for.upcase! if object1_to_search_for
      @object1_search_method = options.fetch(:object1_search_method, :eql?)

      @object2_to_search_for ||= description_to_search_for.fetch(:filename) do
        description_to_search_for.fetch(:object2, false)
      end
      @object2_to_search_for.upcase! if object2_to_search_for
      @object2_search_method = options.fetch(:object2_search_method, :eql?)
    end

  end

  def match_found?
    !found_events.empty?
  end

  # @param [String] source_string
  # @param [String] search_for_string
  # @param [Symbol] method Any string method that will take a string as an argument. Ex: :eql?, :start_with?, :end_with?
  def compare_strings(source_string, search_for_string, method = :eql?); return source_string.send(method, search_for_string); end # compare_strings

  def search_description

  end

  def event_meets_critiera?(event = @event)
    @event_code = event['code']
    unless compare_strings(event_code, event_code_to_search_for, event_code_search_method)
      logger.debug { "No code match: #{event_code} !#{event_code_search_method} #{event_code_to_search_for}" }
      return
    end if event_code_to_search_for

    logger.debug { "Code match: #{event_code} #{event_code_search_method} #{event_code_to_search_for}" }

    if time_to_search_for
      event_time = event['timestamp']
      return unless event_time >= time_start and event_time <= time_end
    end


    if description_search
      case event_code
        when 'PRESENTATION_VIEWED'
          # "Presentation THE SOMETHING COLLECTION 2013 - 2014 was viewed"
          regex = false
        when 'PRESENTATION_VIDEO_VIEWED'
          # "LSGA779L-1 A PYTHAGOREAN THEORIES ON SCREENER.MOV was viewed in presentation THE SOMETHING COLLECTION 2013 - 2014"
          regex = false
        when 'QUICKLINK_VIEW_EMAIL'
          # "user@domain.com viewed 726358-006_DOUG OBERHELMAN CATERPILLER_1.MOV via QuickLink"
          regex = false
        else
          regex = DEFAULT_EVENT_MATCH_REGEX
      end
      if regex
        match = regex.match(event.fetch('description', '')).to_a
        @logger.debug { "Parsed Event Description: #{match.inspect}" }
        if match
          #description_hash = /(?<username>\w*)\s{1}(?<action>[a-z\s]*)\s{1}(?<object1>[A-Z0-9\p{Punct}\s]*)\s?(?<preposition>[a-z\s]*)\s?(?<object2>[A-Z0-9\p{Punct}\s]*)/.match(event.fetch('description', ''))
          username, action, object1, preposition, object2 = match.to_a
          #next unless description_hash['username'] == username_to_search_for if username_to_search_for
          #next unless description_hash['action'] == action_to_search_for     if action_to_search_for
          #next unless description_hash['object1'].strip == object1_to_search_for   if object1_to_search_for
          #next unless description_hash['object2'] == object2_to_search_for if object2_to_search_for

          return unless compare_strings(username, username_to_search_for, username_search_method) if username_to_search_for
          return unless compare_strings(action, action_to_search_for, action_search_method)     if action_to_search_for
          return unless compare_strings(object1.strip, object1_to_search_for, object1_search_method)   if object1_to_search_for
          return unless compare_strings(object2, object2_to_search_for, object2_search_method) if object2_to_search_for
        end
      end
    end

    return true
  end


  def run
    # Events are in an array(stack) going from newest to oldest

    #if search_criteria.empty? or events.empty?
    #  return events.first if occurrence_to_search_for == 1
    #  return events.last  if occurrence_to_search_for == -1
    #  return events if occurrence_to_search_for == -2
    #end

    occurrence_found = false
    events.each { |event|
      @event = event
      next unless event_meets_criteria?

      current_occurrence += 1
      found_events << event

      (occurrence_found = true) and break if occurrence_to_search_for and (current_occurrence == occurrence_to_search_for)

    }
    return false unless match_found?

    if occurrence_to_search_for.is_a?(Integer)
      return found_events.last if occurrence_found or (occurrence_to_search_for == -1)
      return found_events[occurrence_to_search_for] # Could be negative
    end
    return found_events
  end

end