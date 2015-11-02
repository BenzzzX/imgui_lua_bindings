#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
# This works for IMGUI 1.47 WIP and does not get all functions
#
# to use ./generate_imgui_bindings.pl <imgui.h >imgui_iterator.cpp
# and define macros properly as in example imgui_lua_bindings.cpp
#
# check imgui_iterator for explanations of why some functions are not supported yet

my %bannedNames;

#define bannedNames with keys of functions to exclude them
# EXAMPLE:
#my %bannedNames = (
#  "NewFrame" => "banned",
#  "Render" => "banned",
#  "Shutdown" => "banned" );

# This is only useful for ENABLE_IM_LUA_END_STACK
my %endOverride = (
  "PopupModal" => "Popup",
  "PopupContextItem" => "Popup",
  "PopupContextWindow" => "Popup",
  "PopupContextVoid" => "Popup" );


my $line;
my %funcNames;
my %endTypeToInt;
my @endTypes;
while ($line = <STDIN>) {
  #replace ImVec2(x, y) with ImVec2 x, y so it's easier for regex
  $line =~ s/ImVec2\(([^,]*),([^\)]*)\)/ImVec2 $1 $2/g;
  if ($line =~ m/ *IMGUI_API *([^ ]+) *([^\(]+)\(([^\;]*)\);/) {
    print "//" . $line;
    # this will be set to 0 if something is not supported yet
    my $shouldPrint = 1;
    my @args = split(',', $3);
    # things to do before calling real c++ function
    my @before;
    # arguments to real c++ function
    my @funcArgs;
    # things to do after callign real c++ function
    my @after;
    # real c++ function name
    my $funcName = $2;
    if (defined($bannedNames{$funcName})) {
      print "//Not allowed to use this function\n";
      $shouldPrint = 0;
    }
    # c++ type of return value
    my $retType;
    # macro used for calling function
    my $callMacro;
    # if it has a return value (yes I know this is not the cleanest code)
    my $hasRet;
    if ($1 =~ /^void$/) {
      $callMacro = "CALL_FUNCTION_NO_RET";
      $hasRet = 0;
    } elsif ($1 =~ /^bool$/) {
      $callMacro = "CALL_FUNCTION";
      $hasRet = 1;
      push(@funcArgs, "bool");
      push(@after, "PUSH_BOOL(ret)");
    } elsif ($1 =~ /^float$/) {
      $callMacro = "CALL_FUNCTION";
      push(@funcArgs, "float");
      push(@after, "PUSH_NUMBER(ret)");
    } elsif ($1 =~ /^ImVec2$/) {
      $callMacro = "CALL_FUNCTION";
      push(@funcArgs, "ImVec2");
      push(@after, "PUSH_NUMBER(ret.x)");
      push(@after, "PUSH_NUMBER(ret.y)");
    } else {
      print "// Unsupported return type $1\n";
      $shouldPrint = 0;
    }
    for (my $i = 0; $i < @args; $i++) {
      # bool * x = NULL or bool * x
      if ($args[$i] =~ m/^ *bool *\* *([^ =\[]*)( = NULL|) *$/) {
        my $name = $1;
        if ($2 =~ m/^ = NULL$/) {
          push(@before, "OPTIONAL_BOOL_POINTER_ARG($name)");
        } else {
          push(@before, "BOOL_POINTER_ARG($name)");
        }
        push(@funcArgs, $name);
        push(@after, "END_BOOL_POINTER($name)");
        #float a or float a = number
      } elsif ($args[$i] =~ m/^ *float *([^ =\[]*)( *= *[^ ]*|)$/) {
        my $name = $1;
        if ($2 =~ m/^ *= *([^ ]*)$/) {
          push(@before, "OPTIONAL_NUMBER_ARG($name, $1)");
        } else {
          push(@before, "NUMBER_ARG($1)");
        }
        push(@funcArgs, $1);
        # const char* a or const char* a = NULL or "blah"
      } elsif ($args[$i] =~ m/^ *const char\* *([^ =\[]*)( *= *(NULL|".*")|) *$/) {
        my $name = $1;
        if ($2 =~ m/^ *= *NULL$/) {
          push(@before, "OPTIONAL_LABEL_ARG($name)");
        } else {
          push(@before, "LABEL_ARG($name)");
        }
        push(@funcArgs, $name);
        # const ImVec2 a (with default value not supported yet
      } elsif ($args[$i] =~ m/^ *const ImVec2& ([^ ]*) *$/) {
        push(@before, "IM_VEC_2_ARG($1)");
        push(@funcArgs, $1);
        # one of the various enums
        # we are handling these as ints
      } elsif ($args[$i] =~ m/^ *(ImGuiWindowFlags|ImGuiCol|ImGuiStyleVar|ImGuiKey|ImGuiAlign|ImGuiColorEditMode|ImGuiMouseCursor|ImGuiSetCond|ImGuiInputTextFlags|ImGuiSelectableFlags) ([^ ]*)( = 0|) *$/) {
       #These are ints
       my $name = $2;
        if ($3 =~ m/^ = 0$/) {
          push(@before, "OPTIONAL_INT_ARG($name, 0)");
        } else {
          push(@before, "INT_ARG($name)");
        }
        push(@funcArgs, $name);
        #int with default value or not
      } elsif ($args[$i] =~ m/^ *int ([^ =\[]*)( = [^ ]*|) *$/) {
        my $name = $1;
        if ($2 =~ m/^ = ([^ ]*)$/) {
          push(@before, "OPTIONAL_INT_ARG($name, $1)");
        } else {
          push(@before, "INT_ARG($name)");
        }
        push(@funcArgs, $name);
      #unsigned int with default value or not
      } elsif ($args[$i] =~ m/^ *unsigned +int ([^ =\[]*)( = [^ ]*|) *$/) {
        my $name = $1;
        if ($2 =~ m/^ = ([^ ]*)$/) {
          push(@before, "OPTIONAL_UINT_ARG($name, $1)");
        } else {
          push(@before, "UINT_ARG($name)");
        }
        push(@funcArgs, $name);
        # bool with default value or not
      } elsif ($args[$i] =~ m/^ *bool ([^ =\[]*)( *= *true| *= *false|) *$/) {
        my $name = $1;
        if ($2 =~ m/^ *= *([^ ]*)$/) {
          push(@before, "OPTIONAL_BOOL_ARG($name, $1)");
        } else {
          push(@before, "BOOL_ARG($name)");
        }
        push(@funcArgs, $name);
        # we don't support variadic functions yet but we let you use it without extra variables
      } elsif ($args[$i] =~ m/^ *\.\.\. *$/) {
        print "// Variadic functions aren't suppported but here it is anyway\n";
      } else {
        print "// Unsupported arg type " . $args[$i] . "\n";
        $shouldPrint = 0;
      }
    }
    if ($shouldPrint != 0) {
      my $luaFunc = $funcName;
      # Stupid way of implementing overriding
      while($funcNames{$luaFunc}) {
        $luaFunc .= "_" . scalar(@args);
      }
      $funcNames{$luaFunc} = 1;

      print "IMGUI_FUNCTION($luaFunc)\n";
      for (my $i = 0; $i < @before; $i++) {
        print $before[$i] . "\n";
      }

      print $callMacro . "($funcName";
      for (my $i = 0; $i < @funcArgs; $i++) {
        print ", " . $funcArgs[$i];
      }
      print ")\n";

      #for begin and end stack stuff
      if ($funcName =~ m/^Begin(.*)$/) {
        my $curEndType = $1;
        if (defined($endOverride{$1})) {
          $curEndType = $endOverride{$1};
        }
        if (!defined($endTypeToInt{$curEndType})) {
          $endTypeToInt{$curEndType} = scalar(@endTypes);
          push(@endTypes, $curEndType);
        }
        my $curEndTypeInt = $endTypeToInt{$curEndType};
        if ($hasRet) {
          print "IF_RET_ADD_END_STACK($curEndTypeInt)\n";
        } else {
          print "ADD_END_STACK($curEndTypeInt)\n";
        }
      } elsif ($funcName =~ m/^End(.*)$/) {
        my $curEndType = $1;
        if (defined($endOverride{$1})) {
          $curEndType = $endOverride{$1};
        }
        if (!defined($endTypeToInt{$curEndType})) {
          $endTypeToInt{$curEndType} = scalar(@endTypes);
          push(@endTypes, $curEndType);
        }
        my $curEndTypeInt = $endTypeToInt{$curEndType};
        print "POP_END_STACK($curEndTypeInt)\n"
      }

      for (my $i = 0; $i < @after; $i++) {
        print $after[$i] . "\n";
      }
      print "END_IMGUI_FUNC\n";
    }
  } elsif ($line =~ m/^} \/\/ namespace ImGui$/) {
    last;
  }
}
#for end stack stuff
print "END_STACK_START\n";
for (my $i = 0; $i < @endTypes; $i++) {
  print "END_STACK_OPTION($i, " . "End" . $endTypes[$i] .")\n";
}
print "END_STACK_END\n";