#!/bin/sh

# https://github.com/tst2005sh/sh-splitmerge

# format .*-*-8<--* titledata -*->8--*.*

decode_slash() {
	tr \\\\ / | sed -e 's,\(%%\|%2[fF]\),/,g'
}
encode_slash() {
	#sed -e 's,/,%%,g'
	tr / \\\\
}

split_file() {
	if [ $# -eq 0 ]; then
		echo >&2 "Usage: $0 [...] --split <file> [<directory-name>]"
		return 1
	fi
	local f="$1";shift
	if [ ! -f "$f" ]; then
		echo >&2 "$0: No such file $f"
		return 1
	fi
	case "$f" in
		(/*) ;;
		(*) f="$(pwd)/$f" ;;
	esac
	local dst
	if [ $# -eq 0 ]; then
		dst="${f}.d"
	else
		dst="$1";shift
	fi
	case "$dst" in
		(/*);;
		(*) dst="$(pwd)/$dst";;
	esac
	if [ -d "$dst" ]; then
		echo >&2 "destination directory already exists $dst"
		return 1
	fi
	mkdir -- "$dst" || return 2

	local name=''
	local i=0
	while IFS="$(printf '\n')" read -r line; do
		case "$line" in
			(*'->8-'*|*'-8<-'*)
				i=$(($i +1))

				case "$line" in
				(*'-8<-'*'->8-'*)
					name="$(printf '%s\n' "$line" | sed -e 's,^.*-8<--*[[:space:]]\+\(.*\)[[:space:]]\+-*->8-.*$,\1,g')"
				;;
				(*'-8<-'*)
					name="$(printf '%s\n' "$line" | grep '^.*-8<--* ' | sed -e 's,^.*-8<--* \(.*\)$,\1,g')"
				;;
				esac
				continue
			;;
		esac
		local fdst="$(printf %03d $i).$(printf '%s' "${name:-no-name}" | encode_slash).partial.${partialext:-txt}"
		case "$line" in
			(*'title:'*)
				if printf '%s\n' "$line" | grep -q '^[[:space:]]\+title:[[:space:]]\+'; then
					title="$(printf '%s\n' "$line" | sed -e 's/^[[:space:]]\+title:[[:space:]]\+//g')"
					echo >&2 "TITLE=$title"
					ln -r -s "$dst/$fdst" "$dst/$title"
				fi
			;;
		esac
#		if printf '%s\n' "$line" | grep -q '^#.*TAG: '; then
#			i=$(($i +1))
#			local tag="$line"
#			tag="${tag#\#*TAG: }"
#			tag="${tag%%[ 	]*}"
#			lasttag="$tag"
#			echo >&2 "tag: $tag"
#		fi
		printf '%s\n' "$line" >> "$dst/$fdst"
	done < "$f"
}

mergeit() {
	#echo >&2 "... mergeit $1"
	local first=true
	local partialdotext="${partialext:+.$partialext}"
	for f in "$1"/*; do
		[ -e "$f" ] || continue
		case "$f" in
		(*.d) ;;
		(*"$partialdotext") ;;
		(*) continue ;;
		esac

		#[ ! -h "$f" ] || continue
		if [ -f "$f" ] && [ -d "${f}.d" ]; then
			echo >&2 "skip file $f (because $f.d exists)"
			continue
		fi

		local dname="$(dirname "$f")"
		[ "$name" = . ] && dname="" || dname="$dname/"
		dname="$(printf %s "$dname" | decode_slash | sed -e 's,[^.]*\.\([^/]\+\)\.d\(/\),\1\2,g')"

		# 					# file.d/001.title.partial.txt
		local fname="$(basename "$f")" 		#        001.title.partial.txt
		fname="${fname#*.}"			#            title.partial.txt
		fname="${fname%.*}"			#            title.partial
		#fname="${fname%.$partialext}"		#            title.partial
		fname="${fname%.partial}"		#            title

		local name="$dname$fname"
		name="${name#*/}"

		if $first; then
			first=false
		fi
		if ! $first || [ -n "$name" ]; then
			if [ ! -d "$f" ] && ! ${nomarkline:-false}; then
				#printf -- "$cutmark"\\n "$(printf %s "$name" | decode_slash)"
				printf -- %s%s%s%s%s\\n "$prefix" "$markopen" "$(printf %s "$name" | decode_slash)" "$markclose" "$suffix"
			fi
		fi
		if [ -d "$f" ]; then
			#echo >&2 "mergeit $f ..."
			mergeit "$f"
		else
			#echo >&2 "cat $f"
			cat -- "$f"
		fi
	done
}

merge_to_file() {
	local dir="$1";shift;
	#local cutmark='---8<---'
	#local cutmark='---8<--- %s --->8---'
	if [ ! -d "$dir" ]; then
		echo >&2 "$dir is not a directory"
		return 1
	fi
	mergeit "$dir"
}

splitmerge() {
	local action=''
	local prefix=''
	local suffix=''
	local markopen0='8<'
	local markclose0='>8'
	local nomarkline=false
	local n=---
	local partialext=''

	while [ $# -gt 1 ]; do
		case "$1" in
		('-d'|'--dir'|'--merge')	action=merge ;;
		('-f'|'--file'|'--split')	action=split ;;
		('-l'|'--list')		action=list ;;
		('-p'|'--prefix')	shift; prefix="$1";;
		('-s'|'--suffix')	shift; suffix="$1";;
		('-e'|'--ext')		shift; partialext="$1";;
		('-1')			n=-;;
		('-2')			n=--;;
		('-3')			n=---;;
		('-00')			n='-';;
		('-0')			n='';;
		('--raw')		nomarkline=true;;
		('-'[0-9]|'-'[0123][0-9])
			n="$(printf '%'$1's' '' |tr \  -)"
		;;
		(--)			shift;break;;
		(-*)	echo >&2 "Invalid option"; return 1;;
		(*)
			if [ $# -eq 1 ] || [ $# -eq 2 ]; then
				break
			fi
			echo >&2 "Usage: $0 [-p|-s|-n value] -f|-d|-l <input> [<output>]"
			return 1
		;;
		esac
		shift
	done
	local markopen="$n$markopen0$n "
	local markclose=" $n$markclose0$n"
	if [ -z "$n" ]; then
		markopen=''
		markclose=''
	fi
	if [ -z "$partialext" ]; then
		case "$action" in
		("merge")
			partialext="${1%/}"
			partialext="${partialext%.d}"
			partialext="${partialext##*.}"
		;;
		("split")
			partialext="${1##*.}"
		;;
		esac
	fi

	case "$action" in
		(merge)	merge_to_file "$@" ;;
		(split)
			if [ -z "$partialext" ]; then
				echo >&2 "ERROR: partial extension is not defined. Please use --ext"
				exit 1
			fi
			split_file "$@" ;;
		(list)
			if [ -d "$1" ]; then
				ls -1 -- "$1" |
				decode_slash | sed -e 's,[^.]*\.\([^/]\+\)\.d\(/\),\1\2,g' |
				sed -e 's,[^.]*\.\([^/]\+\)\.partial$,\1,g' -e 's,[^.]*\.\([^/]\+\)\.d$,\1/,g'
			else
				grep -- '-8[<>]' "$1" | sed -e 's,^.*-8<--*[[:space:]]\+\(.*\)[[:space:]]\+-*->8--*.*$,\1,g'
			fi
		;;
		(*)
			echo >&2 'Missing action (choose from --merge <dir>, --split <file> or --list <dir|file>)'
			exit 1
		;;
	esac
}

splitmerge "$@"

#case "$1" in
#	(*.d|*.d/)	merge_to_file "$1" ;;
#	(*)		split_file "$1" ;;
#esac

# FEATURE
# merge: suffix/prefix for each mark (to be able to make line like "/* --8<-- ... -->8-- */" )
# merge: or custom open/close mark --open '/* ---8<--- ' --close '--->8--- */'
# merge: garder trace des directory (sauf le 1er qui est le fichier ...) ; utiliser des // ? pour permettre de garder du texte ci/ca en text?

# merge: $0 -d dir
# split: $0 -f file
