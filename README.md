# Ubiquity MediaSilo Library and Command Line Utilities

## Installation

## Setup

## MediaSilo Executable [bin/ubiquity-mediasilo](./bin/ubiquity-mediasilo)
An executable to to interact with the MediaSilo API 

Usage: ubiquity-mediasilo [options]

    --mediasilo-hostname HOSTNAME
                                 The hostname to use when authenticating with the MediaSilo API.
    --mediasilo-username USERNAME
                                 The username to use when authenticating with the MediaSilo API.
    --mediasilo-password PASSWORD
                                 The password to use when authenticating with the MediaSilo API.
    --method-name METHODNAME     The name of the method to invoke.
    --method-args JSON           The arguments to pass to the method
    --log-to FILENAME            Log file location.
                                  default: STDERR
    --log-level LEVEL            Logging level. Available Options: debug, info, warn, error, fatal
                                  default:
    --[no-]options-file [FILENAME]
                                 Path to a file which contains default command line arguments.
                                  default: ~/.options/ubiquity-mediasilo
    -h, --help                   Show this message.
    
#### Example Usage:
    
###### Accessing Help.
./ubiquity-mediasilo --help
    
###### Asset Create
./ubiquity-mediasilo --mediasilo-hostname hostname --mediasilo-username username --mediasilo-password password --method-name asset_create --method-arguments '{ "url" : "http://invalid.net/asset.mov" }'

  - url [String] (Required) The URL of the file to ingest
  - title [String] A title to set on the asset
  - description [String] A description to set on the asset
  - metadata [Hash] The metadata to add to the asset
  - tags_to_add_to_asset [Array] An array of tag names to add to the asset

###### Asset Create Using Path
./ubiquity-mediasilo --mediasilo-hostname hostname --mediasilo-username username --mediasilo-password password --method-name asset_create_using_path --method-arguments '{ "url" : "http://invalid.net/asset.mov", "mediasilo_path" : "Project/Folder/asset.mov" }'

  - mediasilo_path [String] (Required) The MediaSilo path for the file. <Project Name>/[Folder Name]/[Folder Name]/<asset filename>
  - url [String] (Required) The URL of the file to ingest
  - title [String] A title to set on the asset
  - description [String] A description to set on the asset
  - metadata [Hash] The metadata to add to the asset
  - tags_to_add_to_asset [Array] An array of tag names to add to the asset
  - overwrite_existing_asset [Boolean] If true then the existing asset will be deleted and the new asset created. Otherwise an existing asset will be edited.

###### Asset Edit 
./ubiquity-mediasilo --mediasilo-hostname hostname --mediasilo-username username --mediasilo-password password --method-name asset_edit --method-arguments '{ "asset_uuid" : "ASSET-UUUID-AAA-BBBB" }'
    
  - asset_uuid [String] The uuid of the asset to edit
  - title [String] The new title to set on the asset
  - description [String] The new description to set on the asset
  - metadata [Hash] The metadata to update or add to the asset.
  - mirror_metadata [Boolean] If true then metadata not in the metadata hash will be delete from the asset.
  - tags_to_add_to_asset [Array] An array of tag names to add to the asset
  - tags_to_remove_from_asset [Array] An array of tag names to remove from the asset 
  - add_quicklink_to_asset [Boolean|Hash|Array]
  
## MediaSilo Assets to CSV Executable [bin/ubiquity-mediasilo-assets-to-csv](./bin/ubiquity-mediasilo-assets-to-csv)
An executable that allows for the exporting of asset details into CSV
 
Usage: ubiquity-mediasilo-assets-to-csv [options]

    --mediasilo-hostname HOSTNAME
                                 The hostname to use when authenticating with the MediaSilo API.
    --mediasilo-username USERNAME
                                 The username to use when authenticating with the MediaSilo API.
    --mediasilo-password PASSWORD
                                 The password to use when authenticating with the MediaSilo API.
    --[no-]cache-file-path PATH  The name of the method to invoke.
    --csv-file-path PATH         The path and filename of the CSV file to create.
    --search-string STRING       Optionally you can provide a search string and only
    --log-to FILENAME            Log file location.
                                  default: STDERR
    --log-level LEVEL            Logging level. Available Options: debug, info, warn, error, fatal
                                  default: debug
    --[no-]options-file [FILENAME]
                                 Path to a file which contains default command line arguments.
                                  default: ~/.options/ubiquity-mediasilo-assets-to-csv
    --[no-]pretty-print          Determines if the output will be formatted for easier human readability.
    -h, --help                   Show this message.
    
    
#### Example Usage:
    
###### Accessing Help.
./ubiquity-mediasilo-assets-to-csv --help
    