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
# Module:		PackagesUI.ycp
#
# Authors:		Gabriele Strattner (gs@suse.de)
#			Ladislav Slezák <lslezak@novell.com>
#
# Purpose:		Provides common dialogs related to
#			the package management.
#
# $Id$
require "yast"

module Yast
  class PackagesUIClass < Module
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "base"

      Yast.import "Label"
      Yast.import "Wizard"
      Yast.import "HTML"
      Yast.import "String"
      Yast.import "Popup"

      @package_summary = {}
    end

    def GetPackageSummary
      deep_copy(@package_summary)
    end

    def SetPackageSummary(summary)
      summary = deep_copy(summary)
      if summary == nil
        Builtins.y2error("Cannot set nil package summary!")
        return
      end

      Builtins.y2debug("Setting package summary: %1", summary)
      @package_summary = deep_copy(summary)

      nil
    end

    def ResetPackageSummary
      Builtins.y2debug("Resetting package summary")
      @package_summary = {}

      nil
    end

    def SetPackageSummaryItem(name, value)
      value = deep_copy(value)
      if name == nil || name == ""
        Builtins.y2error("Invalid item name: '%1'", name)
        return
      end

      Builtins.y2debug("Package summary '%1': %2", name, value)

      Ops.set(@package_summary, name, value)

      nil
    end


    #
    # Popup displays helptext
    #
    def DisplayHelpMsg(headline, helptext, color, vdim)
      helptext = deep_copy(helptext)
      dia_opt = Opt(:decorated)

      if color == :warncolor
        dia_opt = Opt(:decorated, :warncolor)
      elsif color == :infocolor
        dia_opt = Opt(:decorated, :infocolor)
      end

      header = Empty()
      header = Left(Heading(headline)) if headline != ""

      UI.OpenDialog(
        dia_opt,
        HBox(
          VSpacing(vdim),
          VBox(
            HSpacing(50),
            header,
            VSpacing(0.2),
            helptext, # e.g. `Richtext()
            PushButton(Id(:ok_help), Opt(:default), Label.OKButton)
          )
        )
      )

      UI.SetFocus(Id(:ok_help))

      r = UI.UserInput
      UI.CloseDialog
      deep_copy(r)
    end

    # Display unconfirmed licenses of the selected packages.
    # @return [Boolean] true when all licenses were accepted (or there was no license to confirm)
    def ConfirmLicenses
      ret = true

      to_install = Pkg.GetPackages(:selected, true)
      licenses = Pkg.PkgGetLicensesToConfirm(to_install)

      Builtins.y2milestone("Licenses to confirm: %1", Builtins.size(licenses))
      Builtins.y2debug("Licenses to confirm: %1", licenses)

      display_info = UI.GetDisplayInfo
      size_x = Builtins.tointeger(Ops.get_integer(display_info, "Width", 800))
      size_y = Builtins.tointeger(Ops.get_integer(display_info, "Height", 600))
      if Ops.greater_or_equal(size_x, 800) && Ops.greater_or_equal(size_y, 600)
        size_x = 80
        size_y = 20
      else
        size_x = 54
        size_y = 15
      end

      Builtins.foreach(licenses) do |package, license|
        popup = VBox(
          HSpacing(size_x),
          # dialog heading, %1 is package name
          Heading(Builtins.sformat(_("Confirm Package License: %1"), package)),
          HBox(VSpacing(size_y), RichText(Id(:lic), license)),
          VSpacing(1),
          HBox(
            PushButton(Id(:help), Label.HelpButton),
            HStretch(),
            # push button
            PushButton(Id(:accept), _("I &Agree")),
            # push button
            PushButton(Id(:deny), _("I &Disagree"))
          )
        )
        UI.OpenDialog(popup)
        ui = nil
        while ui == nil
          ui = Convert.to_symbol(UI.UserInput)
          if ui == :help
            ui = nil

            # help text
            help = _(
              "<p><b><big>License Confirmation</big></b><br>\n" +
                "The package in the headline of the dialog requires an explicit confirmation\n" +
                "of acceptance of its license.\n" +
                "If you reject the license of the package, the package will not be installed.\n" +
                "<br>\n" +
                "To accept the license of the package, click <b>I Agree</b>.\n" +
                "To reject the license of the package, click <b>I Disagree</b></p>."
            )

            UI.OpenDialog(
              HBox(
                VSpacing(18),
                VBox(
                  HSpacing(70),
                  RichText(help),
                  HBox(
                    HStretch(),
                    # push button
                    PushButton(Id(:close), Label.CloseButton),
                    HStretch()
                  )
                )
              )
            )
            UI.UserInput
            UI.CloseDialog
          end
        end
        UI.CloseDialog
        Builtins.y2milestone(
          "License of package %1 accepted: %2",
          package,
          ui == :accept
        )
        if ui != :accept
          Pkg.PkgTaboo(package)
          ret = false
        else
          Pkg.PkgMarkLicenseConfirmed(package)
        end
      end

      ret
    end

    # Run helper function, reads the display_support_status feature from the control file
    # @return [Boolean] the read value
    def ReadSupportStatus
      # Load the control file
      Yast.import "ProductControl"
      Yast.import "ProductFeatures"

      ret = ProductFeatures.GetBooleanFeature(
        "software",
        "display_support_status"
      )
      Builtins.y2milestone("Feature display_support_status: %1", ret)
      ret
    end

    # Start the detailed package selection.
    # @param [Hash{String => Object}] options options passed to the widget. All options are optional,
    # if an option is missing or is nil the default value will be used. All options:
    # $[ "enable_repo_mgr" : boolean // display the repository management menu,
    #	    // default: false (disabled)
    #	  "display_support_status" : boolean // display the support status summary dialog,
    #	    // default: depends on the Product Feature "software", "display_support_status"
    #	  "mode" : symbol // package selector mode, no default value, supported values:
    #		`youMode (online update mode),
    #		`updateMode (update mode),
    #		`searchMode (search filter view),
    #		`summaryMode (installation summary filter view),
    #		`repoMode (repositories filter view
    # ]
    #
    # @return [Symbol] Returns `accept or `cancel .
    def RunPackageSelector(options)
      options = deep_copy(options)
      Builtins.y2milestone("Called RunPackageSelector(%1)", options)

      enable_repo_mgr = Ops.get_boolean(options, "enable_repo_mgr")
      display_support_status = Ops.get_boolean(
        options,
        "display_support_status"
      )
      mode = Ops.get_symbol(options, "mode")

      # set the defaults if the option is missing or nil
      if display_support_status == nil
        display_support_status = ReadSupportStatus()
      end

      if enable_repo_mgr == nil
        # disable repository management by default
        enable_repo_mgr = false
      end

      Builtins.y2milestone(
        "Running package selection, mode: %1, options: display repo management: %2, display support status: %3",
        mode,
        enable_repo_mgr,
        display_support_status
      )

      widget_options = Opt()

      widget_options = Builtins.add(widget_options, mode) if mode != nil

      if enable_repo_mgr != nil && enable_repo_mgr
        widget_options = Builtins.add(widget_options, :repoMgr)
      end

      if display_support_status != nil && display_support_status
        widget_options = Builtins.add(widget_options, :confirmUnsupported)
      end

      Builtins.y2milestone(
        "Options for the package selector widget: %1",
        widget_options
      )

      UI.OpenDialog(
        Opt(:defaultsize),
        Ops.greater_or_equal(
          # Note: size(`opt()) = 0 !!
          Builtins.size(widget_options),
          1
        ) ?
          PackageSelector(Id(:packages), widget_options, "") :
          PackageSelector(Id(:packages), "")
      )

      result = Convert.to_symbol(UI.RunPkgSelection(Id(:packages)))

      UI.CloseDialog
      Builtins.y2milestone("Package selector returned %1", result)

      result
    end


    # Start the pattern selection dialog. If the UI does not support the
    # PatternSelector, start the detailed selection with "patterns" as the
    # initial view.
    # @return [Symbol] Return `accept or `cancel
    #
    #
    def RunPatternSelector
      Builtins.y2milestone("Running pattern selection dialog")

      if !UI.HasSpecialWidget(:PatternSelector) ||
          UI.WizardCommand(term(:Ping)) != true
        return RunPackageSelector({}) # Fallback: detailed selection
      end


      # Help text for software patterns / selections dialog
      help_text = _(
        "<p>\n" +
          "\t\t This dialog allows you to define this system's tasks and what software to install.\n" +
          "\t\t Available tasks and software for this system are shown by category in the left\n" +
          "\t\t column.  To view a description for an item, select it in the list.\n" +
          "\t\t </p>"
      ) +
        _(
          "<p>\n" +
            "\t\t Change the status of an item by clicking its status icon\n" +
            "\t\t or right-click any icon for a context menu.\n" +
            "\t\t With the context menu, you can also change the status of all items.\n" +
            "\t\t </p>"
        ) +
        _(
          "<p>\n" +
            "\t\t <b>Details</b> opens the detailed software package selection\n" +
            "\t\t where you can view and select individual software packages.\n" +
            "\t\t </p>"
        ) +
        _(
          "<p>\n" +
            "\t\t The disk usage display in the lower right corner shows the remaining disk space\n" +
            "\t\t after all requested changes will have been performed.\n" +
            "\t\t Hard disk partitions that are full or nearly full can degrade\n" +
            "\t\t system performance and in some cases even cause serious problems.\n" +
            "\t\t The system needs some available disk space to run properly.\n" +
            "\t\t </p>"
        )

      # bugzilla #298056
      # [ Back ] [ Cancel ] [ Accept ] buttons with [ Back ] disabled
      Wizard.OpenNextBackDialog
      Wizard.SetBackButton(:back, Label.BackButton)
      Wizard.SetAbortButton(:cancel, Label.CancelButton)
      Wizard.SetNextButton(:accept, Label.OKButton)
      Wizard.DisableBackButton

      Wizard.SetContents(
        # Dialog title
        # Hint for German translation: "Softwareauswahl und Einsatzzweck des Systems"
        _("Software Selection and System Tasks"),
        PatternSelector(Id(:patterns)),
        help_text,
        false, # has_back
        true
      ) # has_next

      Wizard.SetDesktopIcon("sw_single")

      result = nil
      begin
        result = Convert.to_symbol(UI.RunPkgSelection(Id(:patterns)))
        Builtins.y2milestone("Pattern selector returned %1", result)

        if result == :details
          result = RunPackageSelector({})

          if result == :cancel
            # don't get all the way out - the user might just have
            # been scared of the gory details.
            result = nil
          end
        end
      end until result == :cancel || result == :accept

      Wizard.CloseDialog

      Builtins.y2milestone("Pattern selector returned %1", result)
      result
    end

    def FormatPackageList(pkgs, link)
      pkgs = deep_copy(pkgs)
      ret = ""

      if Ops.greater_than(Builtins.size(pkgs), 8)
        head = Builtins.sublist(pkgs, 0, 8)
        ret = Builtins.sformat(
          "%1... %2",
          Builtins.mergestring(head, ", "),
          HTML.Link(_("(more)"), link)
        )
      else
        ret = Builtins.mergestring(pkgs, ", ")
      end

      ret
    end

    def InstallationSummary(summary)
      summary = deep_copy(summary)
      ret = ""

      if Builtins.haskey(summary, "success")
        ret = HTML.Para(
          HTML.Heading(
            Ops.get_boolean(summary, "success", true) ?
              _("Installation Successfully Finished") :
              _("Package Installation Failed")
          )
        )
      end

      if Builtins.haskey(summary, "error")
        ret = Ops.add(
          ret,
          HTML.List(
            [
              Builtins.sformat(
                _("Error Message: %1"),
                HTML.Colorize(Ops.get_string(summary, "error", ""), "red")
              )
            ]
          )
        )
      end

      items = []

      failed_packs = Builtins.size(Ops.get_list(summary, "failed", []))
      if Ops.greater_than(failed_packs, 0)
        items = Builtins.add(
          items,
          Ops.add(
            Ops.add(
              HTML.Colorize(
                Builtins.sformat(_("Failed Packages: %1"), failed_packs),
                "red"
              ),
              "<BR>"
            ),
            FormatPackageList(
              Builtins.lsort(Ops.get_list(summary, "failed", [])),
              "failed_packages"
            )
          )
        )
      end

      if Ops.greater_than(Ops.get_integer(summary, "installed", 0), 0)
        items = Builtins.add(
          items,
          Ops.add(
            Ops.add(
              Builtins.sformat(
                _("Installed Packages: %1"),
                Ops.get_integer(summary, "installed", 0)
              ),
              "<BR>"
            ),
            FormatPackageList(
              Builtins.lsort(Ops.get_list(summary, "installed_list", [])),
              "installed_packages"
            )
          )
        )
      end

      if Ops.greater_than(Ops.get_integer(summary, "updated", 0), 0)
        items = Builtins.add(
          items,
          Ops.add(
            Ops.add(
              Builtins.sformat(
                _("Updated Packages: %1"),
                Ops.get_integer(summary, "updated", 0)
              ),
              "<BR>"
            ),
            FormatPackageList(
              Builtins.lsort(Ops.get_list(summary, "updated_list", [])),
              "updated_packages"
            )
          )
        )
      end

      if Ops.greater_than(Ops.get_integer(summary, "removed", 0), 0)
        items = Builtins.add(
          items,
          Ops.add(
            Ops.add(
              Builtins.sformat(
                _("Removed Packages: %1"),
                Ops.get_integer(summary, "removed", 0)
              ),
              "<BR>"
            ),
            FormatPackageList(
              Builtins.lsort(Ops.get_list(summary, "removed_list", [])),
              "removed_packages"
            )
          )
        )
      end

      if Ops.greater_than(
          Builtins.size(Ops.get_list(summary, "remaining", [])),
          0
        )
        items = Builtins.add(
          items,
          Ops.add(
            Ops.add(
              Builtins.sformat(
                _("Not Installed Packages: %1"),
                Builtins.size(Ops.get_list(summary, "remaining", []))
              ),
              "<BR>"
            ),
            FormatPackageList(
              Builtins.lsort(Ops.get_list(summary, "remaining", [])),
              "remaining_packages"
            )
          )
        )
      end

      if Ops.greater_than(Builtins.size(items), 0)
        ret = Ops.add(
          ret,
          HTML.Para(Ops.add(HTML.Heading(_("Packages")), HTML.List(items)))
        )
      end

      # reset the items list
      items = []

      if Ops.greater_than(Ops.get_integer(summary, "time_seconds", 0), 0)
        items = Builtins.add(
          items,
          Builtins.sformat(
            _("Elapsed Time: %1"),
            String.FormatTime(Ops.get_integer(summary, "time_seconds", 0))
          )
        )
      end

      if Ops.greater_than(Ops.get_integer(summary, "installed_bytes", 0), 0)
        items = Builtins.add(
          items,
          Builtins.sformat(
            _("Total Installed Size: %1"),
            String.FormatSize(Ops.get_integer(summary, "installed_bytes", 0))
          )
        )
      end

      if Ops.greater_than(Ops.get_integer(summary, "downloaded_bytes", 0), 0)
        items = Builtins.add(
          items,
          Builtins.sformat(
            _("Total Downloaded Size: %1"),
            String.FormatSize(Ops.get_integer(summary, "downloaded_bytes", 0))
          )
        )
      end

      if Ops.greater_than(Builtins.size(items), 0)
        ret = Ops.add(
          ret,
          HTML.Para(Ops.add(HTML.Heading(_("Statistics")), HTML.List(items)))
        )
      end

      items = []

      if Builtins.haskey(summary, "install_log") &&
          Ops.greater_than(
            Builtins.size(Ops.get_string(summary, "install_log", "")),
            0
          )
        items = Builtins.add(
          items,
          HTML.Link(_("Installation log"), "install_log")
        )
      end

      if Ops.greater_than(Builtins.size(items), 0)
        ret = Ops.add(
          ret,
          HTML.Para(Ops.add(HTML.Heading(_("Details")), HTML.List(items)))
        )
      end

      Builtins.y2milestone("Installation summary: %1", ret)

      ret
    end

    def ShowDetailsString(heading, text)
      Popup.LongText(heading, RichText(Opt(:plainText), text), 70, 20)

      nil
    end

    def ShowDetailsList(heading, pkgs)
      pkgs = deep_copy(pkgs)
      ShowDetailsString(
        heading,
        Builtins.mergestring(Builtins.lsort(pkgs), "\n")
      )

      nil
    end


    def ShowInstallationSummaryMap(summary)
      summary = deep_copy(summary)
      summary_str = InstallationSummary(summary)

      if summary_str == nil || summary_str == ""
        Builtins.y2warning("No summary, skipping summary dialog")
        return :next
      end

      wizard_opened = false

      # open a new wizard dialog if needed
      if !Wizard.IsWizardDialog
        Wizard.OpenNextBackDialog
        wizard_opened = true
      end

      dialog = RichText(Id(:rtext), summary_str)

      help_text = _(
        "<P><BIG><B>Installation Summary</B></BIG><BR>Here is a summary of installed packages.</P>"
      )

      Wizard.SetNextButton(:next, Label.FinishButton)

      Wizard.SetContents(
        _("Installation Summary"), #has_next
        dialog,
        help_text,
        true,
        true
      )

      result = nil
      begin
        result = UI.UserInput
        Builtins.y2milestone("input: %1", result)

        # handle detail requests (clicking a link in the summary)
        if Ops.is_string?(result)
          # display installation log
          if result == "install_log"
            ShowDetailsString(
              _("Installation log"),
              Ops.get_string(summary, "install_log", "")
            )
          elsif result == "installed_packages"
            ShowDetailsList(
              _("Installed Packages"),
              Ops.get_list(summary, "installed_list", [])
            )
          elsif result == "updated_packages"
            ShowDetailsList(
              _("Updated Packages"),
              Ops.get_list(summary, "updated_list", [])
            )
          elsif result == "removed_packages"
            ShowDetailsList(
              _("Removed Packages"),
              Ops.get_list(summary, "removed_list", [])
            )
          elsif result == "remaining_packages"
            ShowDetailsList(
              _("Remaining Packages"),
              Ops.get_list(summary, "remaining", [])
            )
          else
            Builtins.y2error("Unknown input: %1", result)
          end
        elsif Ops.is_symbol?(result)
          # close by WM
          result = :abort if result == :cancel
        end
      end while Ops.is_string?(result) ||
        !Builtins.contains([:next, :abort, :back], Convert.to_symbol(result))

      Builtins.y2milestone("Installation Summary result: %1", result)

      Wizard.RestoreNextButton

      if wizard_opened
        # close the opened window
        Wizard.CloseDialog
      end

      Convert.to_symbol(result)
    end

    def ShowInstallationSummary
      ShowInstallationSummaryMap(@package_summary)
    end

    publish :function => :GetPackageSummary, :type => "map <string, any> ()"
    publish :function => :SetPackageSummary, :type => "void (map <string, any>)"
    publish :function => :ResetPackageSummary, :type => "void ()"
    publish :function => :SetPackageSummaryItem, :type => "void (string, any)"
    publish :function => :DisplayHelpMsg, :type => "any (string, term, symbol, integer)"
    publish :function => :ConfirmLicenses, :type => "boolean ()"
    publish :function => :RunPackageSelector, :type => "symbol (map <string, any>)"
    publish :function => :RunPatternSelector, :type => "symbol ()"
    publish :function => :InstallationSummary, :type => "string (map <string, any>)"
    publish :function => :ShowInstallationSummaryMap, :type => "symbol (map <string, any>)"
    publish :function => :ShowInstallationSummary, :type => "symbol ()"
  end

  PackagesUI = PackagesUIClass.new
  PackagesUI.main
end
