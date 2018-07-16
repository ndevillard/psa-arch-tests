#!/usr/bin/perl
#/** @file
# * Copyright (c) 2018, Arm Limited or its affiliates. All rights reserved.
# * SPDX-License-Identifier : Apache-2.0
# *
# * Licensed under the Apache License, Version 2.0 (the "License");
# * you may not use this file except in compliance with the License.
# * You may obtain a copy of the License at
# *
# *  http://www.apache.org/licenses/LICENSE-2.0
# *
# * Unless required by applicable law or agreed to in writing, software
# * distributed under the License is distributed on an "AS IS" BASIS,
# * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# * See the License for the specific language governing permissions and
# * limitations under the License.
#**/
#---------------------------------------------------------------------
# USAGE:
# 1) perl <this_script> <targetConfig_file>
# 2) gcc <generated_C_file> -o <executable_file>
# 3) ./<executable_file>
# 4) Resulting output file is target.hex
#---------------------------------------------------------------------
# THIS SCRIPT :
# 1) Reads the targetConfig.cfg file written in pre-defined format.
# 2) * Generates a C file based on targetConfig, complete with all
#    variable declarations and C syntax formatting.
#    * It will #include val_target.h header file which contains
#    template info about each device described in targetConfig.
#    * This header file is also used by test code to unpack the
#    resulting hex file.
# 3) The autogenerated C file will then be compiled and the resulting
#    executable run to generate target.hex file: which is the packed
#    output of the targetConfig.cfg parameters.
#---------------------------------------------------------------------
# NOTE: Only C-style single line commenting is permitted inside targetConfig.cfg
#---------------------------------------------------------------------

use List::MoreUtils qw(uniq);

$targetConfigPath = $ARGV[0];
$final_output = $ARGV[1];
$output_c = 'targetConfigGen.c';
$input_h = 'val/include/val_target.h';

$final_output_file = undef;
if($final_output =~ /([0-9a-zA-Z_]+)$/) {
	$final_output_file = $1;
}

@unique_devices = undef;

open(IN, $targetConfigPath) or die "Unable to open $targetConfigPath $!";
open(OUT, '>', $output_c) or die "Unable to open: $!";

#---------------------------------------------------------------------
# Open header file and go through enum definition to find group of
# each component; rather than making partner do it. Store in a hash.
#---------------------------------------------------------------------
open(IN0, $input_h) or die "Unable to open: $!";
my %comp_groups;
while(<IN0>) {
    if($_ =~ /COMPONENT_GROUPING/) {
	while($nextline !~ /\}/) {
	    $nextline = <IN0>;
	    #print "$nextline";
	    if($nextline =~ /(\S+)(\s*)\=(\s*)GROUP_([0-9a-zA-Z_]+)(,*)\n/) {
		$comp_groups{$1} = $4;
	    }
	}
    }
}
close IN0;
#print keys %comp_groups, "\n";
#print values %comp_groups, "\n";
#---------------------------------------------------------------------

print OUT '#include "val_target.h"',"\n";
print OUT '#include <stdio.h>',"\n\n";

print OUT "int main\(void\) \{\n";

while(<IN>) {
    if($_ !~ /^\//) {# exclude commented lines

    if($_ =~ /(\S+)\.num(\s*)\=(\s*)(\d+)(\s*)\;/) {
	print OUT lc($comp_groups{uc($1)}),"_desc_t $1\[$4\] = {0};\n";
	print OUT "int $1","_num_instances \= $4\;\n";

	# For each instance of this device
	for ($count = 0; $count < $4; $count++) {
	    print OUT "$1\[$count\]\.cfg_type\.cfg_id \= \(GROUP_",$comp_groups{uc($1)}," << 24\) \+ \(",$comp_groups{uc($1)},"_",uc($1)," << 16\) \+ $count\;\n";
	    print OUT "$1\[$count\]\.cfg_type\.size \= sizeof\($1\)\/$1","_num_instances\;\n";
	    print OUT "$1\[$count\]\.cfg_type\.size \|\= $1","_num_instances << 24\;\n";
	}

	push(@unique_devices, $1);
	push(@unique_groups, $comp_groups{uc($1)});
    }
    #elsif($_ =~ /(\S+)\.(\d+)\.(\S+)(\s*)\=(\s*)(\S+)(\s*)\;/) {
	elsif($_ =~ /(\S+)\.(\d+)\.(\S+)(\s*)\=(\s*)(.+)\;/) {
	print OUT "$1\[$2\]\.$3 \= $6\;\n";
    }
    else {
	print OUT $_;
    }

    }
}

# Remove empty elements from array
@unique_devices = grep { $_ ne '' } @unique_devices;
# Remove duplicate groups
@unique_groups = uniq @unique_groups;
@unique_groups = grep { $_ ne '' } @unique_groups;

#print "@unique_devices\n";
#print "@unique_groups\n\n";

foreach $thisgroup (@unique_groups) {
    print "\nGROUP $thisgroup \n";
    print OUT lc($thisgroup),"_hdr_t group_",lc($thisgroup),"\;\n";
    print OUT "int group_",lc($thisgroup),"_size \= sizeof(group_",lc($thisgroup),"\)\;\n";
    print OUT "int group_",lc($thisgroup),"_count \= 0\;\n";

    print OUT "group_",lc($thisgroup),"\.cfg_type\.cfg_id \= \(GROUP_",$thisgroup," << 24\)\;\n";

    foreach $thisdevice (@unique_devices) {
	if($comp_groups{uc($thisdevice)} eq $thisgroup) {
	    print "DEVICE $thisdevice \n";
	    print OUT "group_",lc($thisgroup),"_size \= group_",lc($thisgroup),"_size \+ sizeof\($thisdevice\)\;\n";
	    print OUT "group_",lc($thisgroup),"_count \= group_",lc($thisgroup),"_count \+ $thisdevice","_num_instances\;\n";

	}
    }
    print OUT "group_",lc($thisgroup),"\.cfg_type\.size \= group_",lc($thisgroup),"_size\;\n";
    print OUT "group_",lc($thisgroup),"\.num \= group_",lc($thisgroup),"_count\;\n";

    print OUT "\n";
}

print OUT "\n";
print OUT "uint32_t\* word_ptr\;\n";
print OUT "int byte_no \= 0\;\n";
#print OUT "int instance_no \= 0\;\n";
#print OUT "int instance_size \= 0\;\n";
#print OUT "device_type_t device_id\;\n";
print OUT "FILE \* fp\;\n";
print OUT "fp \= fopen\(\"",$final_output,"\.h\"\, \"w\"\)\;\n\n";

# Printing out main header inside hex file
#print OUT "fprintf\(fp\, \"#include \\\"pal_fvp_config\.h\\\"\\n\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"#ifndef ",uc($final_output_file),"\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"#define ",uc($final_output_file),"\\n\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"__attribute__\(\(section\(\\\"\.ns_target_database\\\"\)\)\)\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"const uint32_t\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"database[] \= \{\\n\"\)\;\n";

# print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, \"TBSA\"\)\;\n";
# print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, \"_CFG\"\)\;\n";
# print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, \" FVP\"\)\;\n";
# print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, \"_CFG\"\)\;\n";
# TBSA_CFG header
print OUT "fprintf\(fp\, \"0x\%x\"\, \'T\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'B\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'S\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\,\\n\"\, \'A\'\)\;\n";
print OUT "fprintf\(fp\, \"0x\%x\"\, \'_\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'C\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'F\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\,\\n\"\, \'G\'\)\;\n";
# FVP_CFG header
print OUT "fprintf\(fp\, \"0x\%x\"\, \' \'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'F\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'V\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\,\\n\"\, \'P\'\)\;\n";
print OUT "fprintf\(fp\, \"0x\%x\"\, \'_\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'C\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\"\, \'F\'\)\;\n";
print OUT "fprintf\(fp\, \"\%x\,\\n\"\, \'G\'\)\;\n";

print OUT "uint32_t version \= 1\;\n";
print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, version\)\;\n";
#print OUT "fwrite\(\&version\, 4\, 1\, fp\)\;\n";
print OUT "uint32_t total_size \= 0\;\n";

foreach $thisgroup (@unique_groups) {
    print OUT "total_size \= total_size \+ group_",lc($thisgroup),"_size\;\n";
}
# foreach $thisdevice (@unique_devices) {
#     print OUT "total_size \= total_size \+ sizeof\($thisdevice\) \+ \(8\* $thisdevice","_num_instances\)\;\n";
# }
# Add main header size
print OUT "total_size \= total_size \+8 \+8 \+4 \+4 \+4\;\n";
#print OUT "fwrite\(\&total_size\, 4\, 1\, fp\)\;\n\n";
print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, total_size\)\;\n";


foreach $thisgroup (@unique_groups) {
    print OUT "word_ptr \= \(uint32_t \*\)\&group_",lc($thisgroup),"\;\n";
    print OUT "for\(byte_no\=0\; byte_no\<\sizeof\(group_",lc($thisgroup),"\)\; byte_no\=byte_no\+4\)\{\n";
    #print OUT "fwrite\(word_ptr\, 4\, 1\, fp\)\;\n";
    #print OUT "printf\(\"\%08x\,\\n\"\, \*word_ptr\)\;\n";
    print OUT "fprintf\(fp\, \"0x\%08x\,\\n\"\, \*word_ptr\)\;\n";
    print OUT "word_ptr\+\+\;\n";
    print OUT "\}\n";

    foreach $thisdevice (@unique_devices) {
	if($comp_groups{uc($thisdevice)} eq $thisgroup) {
	    print OUT "\tword_ptr \= \(uint32_t \*\)\&","$thisdevice","\[0\]\;\n";
	    print OUT "\tfor\(byte_no\=0\; byte_no\<\sizeof\($thisdevice\)\; byte_no\=byte_no\+4\)\{\n";
	    #print OUT "\tfwrite\(word_ptr\, 4\, 1\, fp\)\;\n";
	    #print OUT "\tprintf\(\"\%08x\,\\n\"\, \*word_ptr\)\;\n";
	    print OUT "\tfprintf\(fp\, \"0x\%08x\,\\n\"\, \*word_ptr\)\;\n";
	    print OUT "\tword_ptr\+\+\;\n";
	    print OUT "\t\}\n";
	}
    }
}
print OUT "fprintf\(fp\, \"0x\%08x\\n\"\, 0xffffffff\)\;\n";
print OUT "fprintf\(fp\, \"\}\;\\n\\n\"\)\;\n";
print OUT "fprintf\(fp\, \"#endif \\n\"\)\;\n";
print OUT "return 0\;\n";


# foreach $thisdevice (@unique_devices) {
#     print OUT "device_id \= DEVICE_ID_", uc $thisdevice, "\;\n";
#     #print OUT "printf\(\"Size of $thisdevice \%lx\\n\"\, sizeof\($thisdevice\)\)\;\n";
#     print OUT "word_ptr \= \&$thisdevice\[0\]\;\n";
#     print OUT "instance_size \= \(sizeof\($thisdevice\)\/$thisdevice","_num_instances\) +4 +4\;\n";
#     print OUT "for\(instance_no\=0\; instance_no\<","$thisdevice","_num_instances\; instance_no\+\+\)\{\n";
#     print OUT "\tprintf\(\"\%x\\n\"\,device_id\)\;\n";
#     print OUT "\tfwrite\(\&device_id\, 4\, 1\, fp\)\;\n";
#     print OUT "\tprintf\(\"\%x\\n\"\,instance_size\)\;\n";
#     print OUT "\tfwrite\(\&instance_size\, 4\, 1\, fp\)\;\n";
#     print OUT "\tfor\(byte_no\=0\; byte_no\<\(sizeof\($thisdevice\)\/$thisdevice","_num_instances\)\; byte_no\=byte_no\+4\)\{\n";
#     print OUT "\t\tprintf\(\"\%x\\n\"\,\*word_ptr\)\;\n";
#     print OUT "\t\tfwrite\(word_ptr\, 4\, 1\, fp\)\;\n";
#     print OUT "\t\tword_ptr\+\+\;\n";
#     print OUT "\t\}\n";
#     print OUT "\}\n\n";

# }

print OUT "\n\}\/\/void main";
