# -*- tcl -*-
# # ## ### ##### ######## ############# #####################
## (C) 2014 Andreas Kupries

# Support package for the core Critcl package.

# Contains the management of the per-file C definitions.

# Originally a part of the critcl package.
# Factored out to
# - reduce the size of the critcl package. 
# - enhance readability and clarity in both critcl and this package.

# # ## ### ##### ######## ############# #####################
## Requirements.

package require Tcl 8.4            ;# Minimal supported Tcl runtime.
package require dict84             ;# Forward-compatible dict command.
# package require lassign84          ;# Forward-compatible lassign command.
package require critcl::cache      ;# Access to result cache.
package require critcl::gopt       ;# Access to global options.
package require critcl::common     ;# General critcl utilities.
package require critcl::data       ;# Access to data files.
package require critcl::meta       ;# Management of teapot meta data.
package require critcl::uuid       ;# Digesting, change detection.
package require critcl::scan       ;# Static Tcl file scanner.

package provide  critcl::cdefs 1
namespace eval ::critcl::cdefs {
    namespace export clear code defs flags func-begin func-cdata \
	func-delete func-done hdrs init ldflags libs objs preload \
	srcs tcls usetcl usetk code? edecls? flags? funcs? hdrs? \
	inits? ldflags? libs? objs? preload? srcs? tcls? usetcl? \
	usetk? func-create-code system-include-paths system-lib-paths
    catch { namespace ensemble create }
}

# # ## ### ##### ######## ############# #####################
## API commands.

proc ::critcl::cdefs::code {ref code} {
    variable fragments
    variable block
    variable defs

    set digest [uuid::add $ref .ccode $code]

    dict lappend fragments $ref $digest
    dict lappend defs      $ref $digest
    dict set     block     $ref $digest $code
    return
}

proc ::critcl::cdefs::defs {ref defines {namespace "::"}} {
    if {![llength $defines]} return

    variable const
    uuid::add $ref .cdefines [list $defines $namespace]

    foreach def $defines {
	dict set const $ref $def $namespace
    }
    return
}

proc ::critcl::cdefs::flags {ref args} {
    if {![llength $args]} return

    variable cflags
    uuid::add $ref .cflags $args

    foreach flag $args {
	dict lappend cflags $ref $flag
    }
    return
}

proc ::critcl::cdefs::func-begin {ref tclname cname details} {
    variable functions
    set digest [uuid::add $ref .function [list $tclname $details]]

    dict lappend functions $ref $cname
    return $digest
}

proc ::critcl::cdefs::func-cdata {ref cname cdata} {
    variable funcdata
    dict set funcdata $ref $cname $cdata
    return
}

proc ::critcl::cdefs::func-delete {ref cname delproc} {
    variable fundelete
    dict set fundelete $ref $cname $delproc
    return
}

proc ::critcl::cdefs::func-done {ref digest code} {
    variable fragments
    variable block

    dict lappend fragments $ref $digest
    dict lappend block     $ref $code
    return
}

proc ::critcl::cdefs::hdrs {ref args} {
    FlagsAndPatterns $ref cheaders $args
    return
}

proc ::critcl::cdefs::init {ref code decl} {
    variable initc
    variable edecls
    uuid::add $ref .cinit [list $code $edecls]

    dict append initc  $ref $code \n
    dict append edecls $ref $edecls  \n
    return
}

proc ::critcl::cdefs::ldflags {ref args} {
    if {![llength $args]} return

    variable ldflags
    uuid::add $ref .ldflags $args

    # Note: Flag may come with and without a -Wl, prefix.
    # We canonicalize this here to always have a -Wl, prefix.
    # This is done by stripping any such prefixes off and then
    # adding it back ourselves.

    foreach flag $args {
	regsub -all {^-Wl,} $flag {} flag
	dict lappend ldflags $ref -Wl,$flag
    }
    return
}

proc ::critcl::cdefs::libs {ref args} {
    FlagsAndPatterns $ref clibraries $args
    return
}

proc ::critcl::cdefs::objs {ref args} {
    # args = list (glob-pattern...) = list (file...)
    if {![llength $args]} return
    variable cobjects

    uuid::add $ref .cobjects $args

    set base [file dirname $ref]
    foreach pattern $args {
	foreach path [common::expand-glob $base $pattern] {
	    # XXX TODO: reject non-file|unreadable paths.

	    # Companion C object file content technically affects
	    # binary. Practically this is only used by the critcl
	    # application to link the package object files with the
	    # bracketing library.
	    #uuid::add $ref .cobject.$path [common::cat $path]
	    dict lappend cobjects $ref $path
	}
    }
    return
}

proc ::critcl::cdefs::preload {ref args} {
    if {![llength $args]} return

    variable preload
    uuid::add $ref .preload $args

    foreach lib $args {
	dict lappend preload $ref $lib
    }
    return
}

proc ::critcl::cdefs::srcs {ref args} {
    # args = list (glob-pattern...) = list (file...)
    if {![llength $args]} return
    variable csources

    uuid::add $ref .csources $args

    set base [file dirname $ref]
    foreach pattern $args {
	foreach path [common::expand-glob $base $pattern] {
	    # Note: This implicitly rejects all paths which are not
	    # readable, nor files.

	    # Companion C file content affects binary.
	    uuid::add $ref .csources.$path [common::cat $path]
	    dict lappend csources $ref $path
	}
    }
    return
}

proc ::critcl::cdefs::tcls {ref args} {
    # args = list (glob-pattern...) = list (file...)
    if {![llength $args]} return
    variable tsources

    # Note: The companion Tcl sources (count, order, content) have no bearing
    #       on the binary. Hence no touching of the uuid system here.

    set base [file dirname $ref]
    foreach pattern $args {
	foreach path [common::expand-glob $base $pattern] {
	    # The scan implicitly rejects paths which are not readable, nor files.
	    dict lappend tsources $ref $path
	    scan-dependencies $ref $path
	}
    }
    return
}

proc ::critcl::cdefs::usetcl {ref version} {
    variable mintcl

    # This is also a dependency we have to record in the meta data.
    # A 'package require' is not needed. This can be inside of the
    # generated and loaded C code.

    dict set mintcl $ref $version
    uuid::add       $ref .mintcl $version
    meta::require   $ref [list Tcl $version]
    return
}

proc ::critcl::cdefs::usetk {ref} {
    variable usetk

    # This is also a dependency we have to record in the meta data.
    # A 'package require' is not needed. This can be inside of the
    # generated and loaded C code.

    dict set usetk $ref 1
    uuid::add      $ref .usetk 1
    meta::require  $ref Tk
    return
}

proc ::critcl::cdefs::code? {ref {mode all}} {
    set sep [common::separator]
    set code {}
    set block [Get $ref block]
    set mode [expr {$mode eq "all" ? "fragments" : "defs"}]
    foreach hash [Get $ref $mode] {
	append code $sep \n [dict get $block $hash]
    }
    return $code
}

proc ::critcl::cdefs::edecls? {ref} {
    Get $ref edecls
}

proc ::critcl::cdefs::flags? {ref} {
    Get $ref flags
}

proc ::critcl::cdefs::funcs? {ref} {
    Get $ref functions
}

proc ::critcl::cdefs::func-create-code {ref cname} {
    set cd [Get $ref funcdata]
    set dp [Get $ref fundelete]

    set cd [expr {[dict exists $cd $cname] ? [dict get $cd $cname] : "NULL"}]
    set dp [expr {[dict exists $dp $cname] ? [dict get $dp $cname] : 0}]

    return "  Tcl_CreateObjCommand(ip, ns_$cname, tcl_$cname, $cd, $dp);"
}

proc ::critcl::cdefs::hdrs? {ref} {
    Get $ref cheaders
}

proc ::critcl::cdefs::inits? {ref} {
    Get $ref initc
}

proc ::critcl::cdefs::ldflags? {ref} {
    Get $ref ldflags
}

proc ::critcl::cdefs::libs? {ref} {
    Get $ref clibraries
}

proc ::critcl::cdefs::objs? {ref} {
    Get $ref cobjects
}

proc ::critcl::cdefs::preload? {ref} {
    Get $ref preload
}

proc ::critcl::cdefs::srcs? {ref} {
    Get $ref csources
}

proc ::critcl::cdefs::tcls? {ref} {
    Get $ref tsources
}

proc ::critcl::cdefs::usetcl? {ref} {
    set required [Get $ref mintcl 8.4]
    foreach version [data::available-tcl] {
	if {[package vsatisfies $version $required]} {
	    return $version
	}
    }
    return $required
}

proc ::critcl::cdefs::usetk? {ref} {
    Get $ref tk 1
}

proc ::critcl::cdefs::system-lib-paths {ref} {
    set paths {}
    set has   {}

    # critcl -L options.
    foreach dir [gopt::get L] {
	+Path has paths $dir
    }

    # Use critcl::clibraries?

    return $paths
}

proc ::critcl::cdefs::system-include-paths {ref} {
    set paths {}
    set has   {}

    # critcl -I options.
    foreach dir [gopt::get I] {
	+Path has paths $dir
    }

    # The result cache is a source of header files too (stubs tables,
    # and other generated files).
    +Path has paths [cache::get]

    # critcl::cheaders
    foreach flag [hdrs? $file] {
	if {![string match "-*" $flag]} {
	    # flag = normalized absolute path to a header file.
	    # Transform into a directory reference.
	    set dir [file dirname $flag]
	} else {
	    # Chop leading -I
	    set dir [string range $flag 2 end]
	}

	+Path has paths $dir
    }

    return $paths
}

proc ::critcl::cdefs::clear {ref} {
    variable block      ; dict unset block      $ref
    variable cflags     ; dict unset cflags     $ref
    variable cheaders   ; dict unset cheaders   $ref
    variable clibraries ; dict unset clibraries $ref
    variable cobjects   ; dict unset cobjects   $ref
    variable const      ; dict unset const      $ref
    variable csources   ; dict unset csources   $ref
    variable defs       ; dict unset defs       $ref
    variable edecls     ; dict unset edecls     $ref
    variable fragments  ; dict unset fragments  $ref
    variable functions  ; dict unset functions  $ref
    variable funcdata   ; dict unset funcdata   $ref
    variable fundelete  ; dict unset fundelete  $ref
    variable initc      ; dict unset initc      $ref
    variable ldflags    ; dict unset ldflags    $ref
    variable mintcl     ; dict unset mintcl     $ref
    variable preload    ; dict unset preload    $ref
    variable tk         ; dict unset tk         $ref
    variable tsources   ; dict unset tsources   $ref
    return
}

# # ## ### ##### ######## ############# #####################
## Internal state

namespace eval ::critcl::cdefs {
    # Per-file (ref) databases of C definitions.

    variable block      {} ;# dict (<ref> -> <hash> -> C-code)    | ccode
    variable cflags     {} ;# dict (<ref> -> list (flag...))      | cflags
    variable cheaders   {} ;# dict (<ref> -> list (flag|file...)) | cheaders
    variable clibraries {} ;# dict (<ref> -> list (flag|file...)) | clibraries
    variable cobjects   {} ;# dict (<ref> -> list (file...))      | cobjects
    variable const      {} ;# dict (<ref> -> <def> -> namespace)  * cdefines
    variable csources   {} ;# dict (<ref> -> list (file...))      | csources
    variable defs       {} ;# dict (<ref> -> list (hash...))      * ccode
    variable edecls     {} ;# dict (<ref> -> C-code)              | cinit
    variable fragments  {} ;# dict (<ref> -> list (hash...))      | ccode    ccommand cproc
    variable functions  {} ;# dict (<ref> -> list (C-name...))    |          ccommand cproc
    variable funcdata   {} ;# dict (<ref> -> cname -> cdata)      |          ccommand
    variable fundelete  {} ;# dict (<ref> -> cname -> delfunc)    |          ccommand
    variable initc      {} ;# dict (<ref> -> C-code)              | cinit
    variable ldflags    {} ;# dict (<ref> -> list (flag...))      | ldflags
    variable mintcl     {} ;# dict (<ref> -> version)             | tcl
    variable preload    {} ;# dict (<ref> -> list (libname...))   | preload
    variable tk         {} ;# dict (<ref> -> bool|presence)       | tk
    variable tsources   {} ;# dict (<ref> -> list (file...))      | tsources

    #	tsources	- List. The companion tcl sources for <file>.
    #	cheaders	- List. The companion C header files for <file>.
    #	csources	- List. The companion C sources for <file>.
    #	clibraries	- List. Companion libraries to link.
    #	cflags		- List. Additional flags to provide to the compile step.
    #	ldflags		- List. Additional flags to provide to the link step.
    #	initc		- String. Initialization code for Foo_Init(), "critcl::cinit"
    #	edecls		- String. Declarations of externals needed by Foo_Init(), "critcl::cinit"
    #	functions	- List. Collected function names.
    #	fragments	- List. Hashes of the collected C source bodies (functions, and unnamed code).
    #	block		- Dictionary. Maps the hashes (see 'fragments') to the actual C sources.
    #	defs		- List. Hashes of the collected C source bodies (only unnamed code), for extraction of defines.
    #	const		- Dictionary. Maps the names of defines to the namespace the associated variables will be put into.
    #	mintcl		- String. Minimum version of Tcl required by the package.
    #	preload		- List. Names of all libraries to load
    #			  before the package library. This
    #			  information is used only by mode
    #			  'generate package'. This means that
    #			  packages with preload can't be used
    #			  in mode 'compile & run'.

    namespace eval cache  { namespace import ::critcl::cache::*  }
    namespace eval common { namespace import ::critcl::common::* }
    namespace eval data   { namespace import ::critcl::data::*   }
    namespace eval gopt   { namespace import ::critcl::gop::*    }
    namespace eval meta   { namespace import ::critcl::meta::*   }
    namespace eval uuid   { namespace import ::critcl::uuid::*   }
    namespace import ::critcl::scan-dependencies
}

# # ## ### ##### ######## ############# #####################
## Internal support commands

proc ::critcl::cdefs::+Path {hv pv path} {
    upvar 1 $hv has $pv pathlist
    if {[dict exists $has $dir]} continue
    dict set has $dir yes
    lappend pathlist $path
    return
}

proc ::critcl::cdefs::Get {ref dbvar {default {}}} {
    variable $dbvar
    upvar 0  $dbvar data
    if {![dict exists $data $ref]} { return $default }
    return [[dict get $data $ref]
}

proc ::critcl::cdefs::FlagsAndPatterns {ref dbvar words} {
    # args = list (flag|glob-pattern...) = list (flag|file...)
    if {![llength $words]} return
    variable $dbvar
    upvar 0  $dbvar options

    uuid::add $ref .$dbvar $args

    set base [file dirname $ref]

    # args is intermingled flags (-*) and glob-patterns.  Flags are
    # passed through unchanged. Patterns are expanded.  Contents
    # indirectly affect the binary, and are therefore digested.

    foreach flagOrPattern $args {
	if {[string match "-*" $flagOrPattern]} {
	    # Flag, pass unchanged
	    dict lappend options $ref $flagOrPattern
	} else {
	    # Pattern. Expand, pass the found files.
	    foreach path [common::expand-glob $base $flagOrPattern] {
		uuid::add $ref .$dbvar.$path [common::cat $path]
		dict lappend options $ref $path
	    }
	}
    }
    return
}

proc ::critcl::cdefs::Error {msg args} {
    set code [linsert $args 0 CRITCL CDEFS]
    return -code error -errorcode $code $msg
}

# # ## ### ##### ######## ############# #####################
## Initialization

# -- none --

# # ## ### ##### ######## ############# #####################
## Ready
return