<#
	.NOTES

	Copyright (c) Microsoft Corporation.
	Licensed under the MIT License.

	.SYNOPSIS

	Capture and View an ETW trace:
	Network Activity

	.DESCRIPTION

	.\TraceNetwork Start [-Loop] [-CLR] [-JS]
	.\TraceNetwork Stop [-WPA [-FastSym]]
	.\TraceNetwork View [-Path <path>\MSO-Trace-Network.etl|.wpapk] [-FastSym]
	.\TraceNetwork Status
	.\TraceNetwork Cancel
	    -Loop: Record only the last few minutes of activity (circular memory buffer). 
	    -CLR:  Resolve call stacks for C# (Common Language Runtime).
	    -JS:   Resolve call stacks for JavaScript.
	    -WPA:  Launch the WPA viewer (Windows Performance Analyzer) with the collected trace.
	    -FastSym: Load symbols only from cached/transcoded SymCache, not from slower PDB files.
	              See: https://github.com/microsoft/MSO-Scripts/wiki/Advanced-Symbols#optimize
	    -Path: Optional path to a previously collected trace.
	    -Verbose

	.LINK

	https://github.com/microsoft/MSO-Scripts/wiki/Network-Activity
	https://learn.microsoft.com/en-us/windows-hardware/test/wpt/event-tracing-for-windows
	https://learn.microsoft.com/en-us/shows/defrag-tools/39-windows-performance-toolkit
#>

[CmdletBinding(DefaultParameterSetName = "View")]
Param(
	# "Start, Stop, Status, Cancel, View"
	[Parameter(Position=0)]
	[string]$Command,

	# Record only the last few minutes of activity (circular memory buffer).
	[Parameter(ParameterSetName="Start")]
	[switch]$Loop,

	# "Support Common Language Runtime / C#"
	[Parameter(ParameterSetName="Start")]
	[switch]$CLR,

	# "Support JavaScript"
	[Parameter(ParameterSetName="Start")]
	[switch]$JS,

	# "Launch WPA after collecting the trace"
	[Parameter(ParameterSetName="Stop")]
	[switch]$WPA,

	# "Optional path to a previously collected trace: MSO-Trace-Network.etl"
	[Parameter(ParameterSetName="View")]
	[string]$Path = $Null,

	# "Faster symbol resolution by loading only from SymCache, not PDB"
	[Parameter(ParameterSetName="Stop")]
	[Parameter(ParameterSetName="View")]
	[switch]$FastSym

	# [switch]$Verbose # implicit
)

# ===== MODIFY THIS =====
	$TraceParams =
	@{
		RecordingProfiles =
		@(
			# This XML file contains tracing parameters organized by ProfileName.
			# To see the available profiles, run: wpr -profiles .\WPRP\Network.wprp
			".\WPRP\Network.wprp!NetworkFull" # or Network.15002.wprp - See ReadMe.txt
			".\WPRP\EdgeChrome.wprp!MSEdge_Basic" # or EdgeChrome.15002.wprp
			".\WPRP\OfficeProviders.wprp!CodeMarkers" # Code Markers, HVAs, other light logging

		<#
			^^^ The first entry is the base recording profile for this script.
			vvv Additional recording profile string(s) follow. See ReadMe.txt

			"Registry" # Built-in
			".\WPRP\FileDiskIO.wprp!FileIO"
			"c:\MyProfiles\MyRecordingProfile.wprp!CustomProfile"

			Other recording profiles can be added via the WPT_WPRP environment variable.
			$Env:WPT_WPRP="c:\path\MyProfile.wprp!ProfileName;c:\path\MyProfile2.wprp!ProfileName2"
			set WPT_WPRP=c:\path\MyProfile.wprp!ProfileName;c:\path\MyProfile2.wprp!ProfileName2

			Other recording providers can be added via the WPT_XPERF environment variable (in "XPerf -ON" format).
			$Env:WPT_XPERF="GUIDorNAME1 + GUIDorNAME2:::Stack + GUIDorNAME3:KeywordFlags:Level + ..."
			set WPT_XPERF=GUIDorNAME1 + GUIDorNAME2:::Stack + GUIDorNAME3:KeywordFlags:Level + ...

			See: https://github.com/microsoft/MSO-Scripts/wiki/Customize-Tracing#envvar
		#>
		)

		ProviderManifests =
		@(
			# Optional: Register Office ETW Provider Manifests not registered by default.
			# See: .\OETW\ReadMe.txt and .\BETA\OETW\ReadMe.txt
			# ".\BETA\OETW\EdgeETW.man"
			# ".\BETA\OETW\ChromeETW.man"
			".\OETW\MsoEtwTP.man" # Office Task Pool
			".\OETW\MsoEtwCM.man" # Office Idle Manager
			".\OETW\MsoEtwDQ.man" # Office Dispatch Queue
		)

		# This is the arbitrary name of the tracing session/instance.
		InstanceName = "MSO-Trace-Network"
	}

	$ViewerParams =
	@{
		# The configuration files define the data tabs in the WPA viewer.
		# https://learn.microsoft.com/en-us/windows-hardware/test/wpt/view-profiles
		ViewerConfig = ".\WPAP\BasicInfo.wpaProfile", ".\WPAP\EdgeRegions.wpaProfile", ".\WPAP\Network.wpaProfile"

		# The trace file name is: <InstanceName>.etl
		TraceName = $TraceParams.InstanceName

		# Optional alternate path to a previously collected ETL trace:
		TraceFilePath = $Path
	}

# ===== END MODIFY ====

if (!$script:PSScriptRoot) { $script:PSScriptRoot = Split-Path -Parent -Path $script:MyInvocation.MyCommand.Definition } # for PSv2
$script:ScriptHomePath = $PSScriptRoot
$script:ScriptRootPath = $PSScriptRoot
$script:PSScriptParams = $script:PSBoundParameters # volatile

. "$ScriptRootPath\INCLUDE.ps1"

# Main

	$Result = ProcessTraceCommand $Command @TraceParams -Loop:$Loop -CLR:$CLR -JS:$JS

	switch ($Result)
	{
	Started   { Write-Msg "ETW Network tracing has begun.`nExercise the application, then run: $(GetScriptCommand) Stop [-WPA]`n" }
	Collected { WriteTraceCollected $TraceParams.InstanceName } # $WPA switch
	View      { $WPA = $True }
	Success   { $WPA = $False }
	Error     { exit 1 }
	}

	if ($WPA)
	{
		LaunchViewer @ViewerParams -FastSym:$FastSym

		# They probably want to view the trace using the NetBlame addin, if available: BETA\TraceNetwork View

		$Command = "$script:ScriptRootPath\BETA\$($script:MyInvocation.MyCommand)"
		if (Test-Path -PathType Leaf $Command -ErrorAction:SilentlyContinue)
		{
			Write-Info "For easier analysis, please try the BETA version:"
			$Command = "BETA\$(GetScriptCommand) View"
			if ($FastSym) { $Command += " -FastSym" }
			Write-Info $Command
		}
	}

exit 0 # Success
