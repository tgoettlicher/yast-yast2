# encoding: utf-8

# ***************************************************************************
#
# Copyright (c) 2002 - 2012 Novell, Inc.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#
# ***************************************************************************
# File:	modules/ProductFetures.ycp
# Package:	installation
# Summary:	Product features
# Authors:	Anas Nashif <nashif@suse.de>
#              Jiri Srain <jsrain@suse.cz>
#
# $Id$
require "yast"

module Yast
  class ProductFeaturesClass < Module
    def main
      textdomain "base"

      Yast.import "Misc"
      Yast.import "Mode"
      Yast.import "Stage"

      # Map of all features
      # See defaults map below for sample contents
      @features = nil

      # Default values for features
      # two-level map, section_name -> [ feature -> value ]
      @defaults = {
        "globals"      => {
          "incomplete_translation_treshold" => "95",
          "ui_mode"                         => "expert",
          "enable_autologin"                => true,
          "language"                        => "",
          "skip_language_dialog"            => false,
          "keyboard"                        => "",
          "runlevel"                        => "",
          "timezone"                        => "",
          "fam_local_only"                  => "never",
          "enable_firewall"                 => true,
          "firewall_enable_ssh"             => false,
          "additional_kernel_parameters"    => "",
          "flags"                           => [],
          "run_you"                         => true,
          "relnotesurl"                     => "",
          "vendor_url"                      => "",
          "enable_clone"                    => false,
          # FATE #304865
          "base_product_license_directory"  => "/etc/YaST2/licenses/base/"
        },
        "partitioning" => {
          "use_flexible_partitioning"    => false,
          "flexible_partitioning"        => {},
          "vm_keep_unpartitioned_region" => false
        },
        "software"     => {
          "software_proposal"                    => "selection",
          "selection_type"                       => :auto,
          "delete_old_packages"                  => true,
          "only_update_installed"                => false,
          "packages_transmogrify"                => "",
          "base_selection"                       => "",
          "packages"                             => [],
          "kernel_packages"                      => [],
          "addon_selections"                     => [],
          "inform_about_suboptimal_distribution" => false
        },
        "network"      => { "force_static_ip" => false }
      }
    end

    # Initialize default values of features
    # @param [Boolean] force boolean drop all settings which were set before
    def InitFeatures(force)
      return if !(force || @features == nil)
      @features = deep_copy(@defaults)

      nil
    end

    # Set a feature section
    # Default values will be used where value not defined
    # @note This is a stable API function
    # @param section name string the name of the section
    # @param [Hash{String => Object}] section_map a map containing data of the section
    def SetSection(section_name, section_map)
      section_map = deep_copy(section_map)
      InitFeatures(false)
      Builtins.y2debug("Setting section: %1", section_name)
      section_map = Convert.convert(
        Builtins.union(Ops.get(@defaults, section_name, {}), section_map),
        :from => "map",
        :to   => "map <string, any>"
      )
      Ops.set(@features, section_name, section_map)

      nil
    end

    # Get a complete section for evaluation
    # @note This is a stable API function
    # @param [String] section_name string name of the section
    # @return a map key->value, options in the section
    def GetSection(section_name)
      InitFeatures(false)
      Ops.get(@features, section_name, {})
    end

    # Save product features
    # @note This is a stable API function
    def Save
      InitFeatures(false)
      if Mode.update # in case of update old file has different format
        SCR.Execute(
          path(".target.bash"),
          "test -f /etc/YaST2/ProductFeatures && /bin/rm /etc/YaST2/ProductFeatures"
        )
      end
      Builtins.foreach(@features) { |group, options| Builtins.foreach(options) do |key, value|
        if Ops.is_map?(value) || Ops.is_list?(value) || Ops.is_symbol?(value)
          Builtins.y2debug("Skipping option %1", key)
        else
          strval = GetStringFeature(group, key)
          SCR.Write(
            Ops.add(Ops.add(path(".product.features.value"), group), key),
            strval
          )
        end
      end }
      SCR.Write(path(".product.features"), nil) # flush

      nil
    end

    # Restore product features in running system
    # @note This is a stable API function
    def Restore
      InitFeatures(true)
      groups = SCR.Dir(path(".product.features.section"))
      Builtins.foreach(groups) do |group|
        Ops.set(@features, group, Ops.get(@features, group, {}))
        values = SCR.Dir(Ops.add(path(".product.features.value"), group))
        Builtins.foreach(values) do |v|
          Ops.set(
            @features,
            [group, v],
            SCR.Read(
              Ops.add(Ops.add(path(".product.features.value"), group), v)
            )
          )
        end
      end

      nil
    end

    # Initialize the features structure if needed
    # @note This is a stable API function
    # Either read from /etc/YaST2/ProductFeatures or set default values
    def InitIfNeeded
      return if @features != nil
      if Stage.normal || Stage.firstboot
        Restore()
      else
        InitFeatures(false)
      end

      nil
    end

    # Get value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @return [Object] the feature value
    def GetFeature(section, feature)
      InitIfNeeded()
      ret = Ops.get(@features, [section, feature])
      ret = "" if ret == nil
      deep_copy(ret)
    end

    # Get value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @return [String] the feature value
    def GetStringFeature(section, feature)
      value = GetFeature(section, feature)
      if value == nil
        return nil
      elsif Ops.is_string?(value)
        return Convert.to_string(value)
      elsif Ops.is_boolean?(value)
        return Convert.to_boolean(value) ? "yes" : "no"
      else
        return Builtins.sformat("%1", value)
      end
    end

    # Get value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @return [Boolean] the feature value
    def GetBooleanFeature(section, feature)
      value = GetFeature(section, feature)
      if value == nil
        return nil
      elsif Ops.is_boolean?(value)
        return Convert.to_boolean(value)
      elsif Ops.is_string?(value) &&
          Builtins.tolower(Convert.to_string(value)) == "yes"
        return true
      else
        return false
      end
    end

    # Get value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @return [Fixnum] the feature value
    def GetIntegerFeature(section, feature)
      value = GetFeature(section, feature)
      if value == nil
        return nil
      elsif Ops.is_integer?(value)
        return Convert.to_integer(value)
      elsif Ops.is_string?(value)
        return Builtins.tointeger(Convert.to_string(value))
      else
        return nil
      end
    end

    # Set value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @param [Object] value any the feature value
    def SetFeature(section, feature, value)
      value = deep_copy(value)
      InitIfNeeded()
      Ops.set(@features, section, {}) if !Builtins.haskey(@features, section)
      Ops.set(@features, [section, feature], value)

      nil
    end

    # Set value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @param [String] value string the feature value
    def SetStringFeature(section, feature, value)
      SetFeature(section, feature, value)

      nil
    end

    # Set value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @param [Boolean] value boolean the feature value
    def SetBooleanFeature(section, feature, value)
      SetFeature(section, feature, value)

      nil
    end

    # Set value of a feature
    # @note This is a stable API function
    # @param [String] section string section of the feature
    # @param features string feature name
    # @param [Fixnum] value integer the feature value
    def SetIntegerFeature(section, feature, value)
      SetFeature(section, feature, value)

      nil
    end

    # Exports the current set of ProductFeatures
    #
    # @return [Hash <String, Hash{String => Object>}] features
    def Export
      deep_copy(@features)
    end

    # Imports product features
    #
    # @param map <string, map <string, any> > features
    def Import(import_settings)
      import_settings = deep_copy(import_settings)
      @features = deep_copy(import_settings)

      nil
    end

    publish :function => :GetStringFeature, :type => "string (string, string)"
    publish :function => :SetSection, :type => "void (string, map <string, any>)"
    publish :function => :GetSection, :type => "map <string, any> (string)"
    publish :function => :Save, :type => "void ()"
    publish :function => :Restore, :type => "void ()"
    publish :function => :InitIfNeeded, :type => "void ()"
    publish :function => :GetFeature, :type => "any (string, string)"
    publish :function => :GetBooleanFeature, :type => "boolean (string, string)"
    publish :function => :GetIntegerFeature, :type => "integer (string, string)"
    publish :function => :SetFeature, :type => "void (string, string, any)"
    publish :function => :SetStringFeature, :type => "void (string, string, string)"
    publish :function => :SetBooleanFeature, :type => "void (string, string, boolean)"
    publish :function => :SetIntegerFeature, :type => "void (string, string, integer)"
    publish :function => :Export, :type => "map <string, map <string, any>> ()"
    publish :function => :Import, :type => "void (map <string, map <string, any>>)"
  end

  ProductFeatures = ProductFeaturesClass.new
  ProductFeatures.main
end
