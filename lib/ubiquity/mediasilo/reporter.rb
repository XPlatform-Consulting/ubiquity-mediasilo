class Ubiquity::MediaSilo::Reporter

  class << self

    attr_accessor :logger, :ms

    def get_assets_using_search_string(search_string, options = { })
#response = ms.asset_advanced_search("( and metadatakeys:'Module ID' (and datecreated:1398211200..1403654400) )", { 'page' => -1, 'searchGlobal' => true }, { :add_folder_crumbs_as_hash => true })
#response = ms.asset_advanced_search("( and metadatakeys:'Module ID' (and datecreated:1398211200..) )", { 'page' => 1, 'searchGlobal' => true }, { :add_folder_crumbs_as_hash => true })
#response = ms.asset_advanced_search("( and metadatakeys:'Module ID' (and datecreated:1398211200..) )", { 'page' => -1 }, { :add_folder_crumbs_as_hash => true })
      response = ms.asset_advanced_search_extended(search_string, { 'page' => -1 }, { :add_folder_crumbs_as_hash => true })
      assets = response['ASSETS']
      assets.map! { |asset| asset['metadata'] = ms.metadata_transform_hash(( ms.metadata_get_by_asset_uuid(asset['uuid']) || [ { 'METADATA' => [ ] } ] ).first['METADATA']) ; asset } if options[:include_metadata]
      assets
    end

    def get_all_assets_for_folder(project_id, folder, options = { })
      include_sub_folders = options[:include_subfolders]
      folder_id = folder['FOLDERID']

      folder_assets = ms.asset_get_by_folder_id(folder_id, options)
      return [ ] unless folder_assets
      assets = folder_assets.dup

      if options[:include_search_data]
        parent_search_data = options[:search_data] || { 'workspaceid' => project_id, 'folder_crumbs_as_hash' => { } }

        folder_name = folder['FOLDERNAME']
        #folder_crumb = { folder_id => folder_name }

        search_data = parent_search_data.dup
        search_data['folder_crumbs_as_hash'][folder_id] = folder_name
        options[:search_data] = search_data
        assets.map { |asset| asset['searchdata'] = search_data }
      end

      if include_sub_folders
        folders = ms.folder_get_by_parent_id(project_id, folder_id)
        folders.each { |_folder| assets += get_all_assets_for_folder(project_id, _folder, options) }
      end
      assets
    end

    def get_all_assets_for_project(project, options = { })
      include_sub_folders = options[:include_sub_folders]

      project_id = project['PROJECTID']
      project_name = project['NAME']

      project_assets = ms.asset_get_by_project_id(project_id, options)
      return [ ] unless ms.success?
      assets = project_assets.dup

      _response = ms.response
      loop do
        _response = _response.request.get_next_page
        result = _response.result
        #puts "RESULT TYPE: #{result.inspect}"
        assets += result if result
        break unless _response.success? and _response.next_page?
      end if _response.next_page?

      if options[:include_search_data]
        search_data = { 'workspaceid' => project_id.to_s, 'workspacename' => project_name, 'folderid' => '0', 'foldername' => '', 'folder_crumbs_as_hash' => { project_id => project_name } }
        assets.map { |asset| asset['searchdata'] = search_data }
        options[:search_data] = search_data.dup
      end

      if include_sub_folders
        folders = ms.folder_get_by_parent_id(project_id, 0)
        folders.each { |folder| assets += get_all_assets_for_folder(project_id, folder, options) }
      end

      # assets.map! do |asset|
      #   search_data = asset['searchdata']
      #   foldercrumbs = search_data['foldercrumbs']
      #   folder_crumbs_as_hash = Hash[ foldercrumbs.map { |foldercrumb| foldercrumb.first }  ]
      #   #folder_crumbs_as_hash = Hash[ foldercrumbs.keys.zip(foldercrumbs.values) ]
      #   search_data['folder_crumbs_as_hash'] = folder_crumbs_as_hash
      #   asset['searchdata'] = search_data
      #   asset
      # end if options[:include_search_data]

      assets
    end


    def get_assets_by_project(projects = nil)
      projects ||= ms.project_get_all.first(5) #.map { |project| project['PROJECTID'] }

      _assets = [ ]
      [*projects].each { |project|
        _assets += get_all_assets_for_project(project, :include_search_data => true, :include_sub_folders => true, :page => :all, :pagesize => 200) #, page: 1, pagesize: 1)
      }
      _assets
    end

    def asset_to_record(_asset)
      asset = _asset.dup
      metadata = asset.delete('metadata') { [ ] }
      file_access = asset.delete('fileaccess') { { } }
      searchdata = asset.delete('searchdata') { { } }
      tags = asset.delete('tags') { [ ] }

      project_id = searchdata['workspaceid']
      project_name = searchdata['workspacename']

      #metadata = ms.metadata_transform_hash(metadata)
      metadata = Hash[ metadata.map { |cm| [ "metadata:#{cm['key']}", cm['value'] ] } ]
      foldercrumbs = searchdata['foldercrumbs']
      folder_crumbs_hash = searchdata['folder_crumbs_as_hash']
      folder_crumbs_hash ||= Hash[ foldercrumbs.map { |foldercrumb| foldercrumb.first }  ]
      #folder_crumbs_hash = searchdata.delete('folder_crumbs_as_hash')
      #puts "Folder Crumbs Hash: #{folder_crumbs_hash}"
      #pp _asset

      mediasilo_path = "#{folder_crumbs_hash.values.join('\\')}\\#{asset['title']}"
      stream = file_access.delete('stream')
      stream = stream ? Hash[ stream.map { |k,v| [ "stream:#{k}", v ] } ] : { }

      asset['tags'] = JSON.generate(tags)
      asset['mediasilo_path'] = mediasilo_path
      asset['project_name'] = project_name
      asset['size_in_bytes'] = asset['size'] * 1000
      asset.merge!(searchdata)
      asset.merge!(file_access)
      asset.merge!(metadata)
      asset.merge!(stream)

      asset
    end

# Builds a "Table" consisting of a row of column headers and then the values for each asset as an individual row
    def assets_to_table(assets)
      fields = [ ]
      assets.map! do |asset|
        _asset = asset_to_record(asset)
        fields = fields | _asset.keys
        _asset
      end
      fields = fields.sort
      table = [ fields ] + assets.map { |asset| fields.map { |field_name| asset[field_name] } }
      table
    end

# Writes Table Rows to a CSV File.
    def output_to_csv(rows, destination_file_path)
      logger.debug { "Outputting to CSV File. '#{destination_file_path}'" }
      total_rows = rows.length
      CSV.open(destination_file_path, 'w') { |writer|
        rows.each_with_index do |row, idx|
          logger.debug { "Writing Row #{idx+1} of #{total_rows}" }
          writer << row
        end
      }
      logger.info { "Output Saved to CSV File. '#{destination_file_path}'" }
    end

  end

end
