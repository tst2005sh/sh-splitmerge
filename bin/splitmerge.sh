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
string2regexp_grep() { sed -e 's/\([.*\[]\)/\\\1/g'; }

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
	local i=${startnumber:-1}
	while IFS="$(printf '\n')" read -r line; do
		case "$line" in
			(*'->8-'*|*'-8<-'*)
				case "$line" in
				(*'-8<-'*'->8-'*)
					name="$(printf '%s\n' "$line" | sed -e 's,^.*-8<--*[[:space:]]\+\(.*\)[[:space:]]\+-*->8-.*$,\1,g')"
				;;
				(*'-8<-'*)
					name="$(printf '%s\n' "$line" | grep '^.*-8<--* ' | sed -e 's,^.*-8<--* \(.*\)$,\1,g')"
				;;
				esac
				i=$(($i +1))
				continue
			;;
		esac
		local fdst="$(printf %03d $i).$(printf '%s' "${name:-no-name}" | encode_slash)${partial}${ext:-txt}"
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
	for f in "$1"/*; do
		[ -e "$f" ] || continue
		case "$f" in
		(*.d) ;;
		(*"$ext") ;;
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
		#fname="${fname%$ext}"			#            title.partial
		fname="${fname%$partial}"		#            title

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
	local partial='.partial'
	local ext=''
	local startnumber=1

	while [ $# -gt 1 ] || [ "$1" = --help ]; do
		case "$1" in
		('--help')
			echo 'Usage: '"$0"' [options] --split <src-file> [dest-dir]'
			echo 'Usage: '"$0"' [options] --merge <src-dir>'
			echo 'Usage: '"$0"' [options] --list <src-file|src-dir>'
			echo
			echo 'Actions:'
			echo '  -f|--file|--split'
			echo '  -d|--dir|--merge'
			echo '  -l|--list'
			echo 
			echo '  --split <src-file>             ...'
			echo '  --split <src-file> <dest-dir>  ...'
			echo '  --merge <src-dir>              ...'
			echo '  --list <src-file>              ...'
			echo '  --list <src-dir>               ...'
			echo
			echo 'Options:'
			echo '  -p|--prefix <text>          insert <text> before the mark'
			echo '  -s|--suffix <text>          insert <text> after the mark'
			echo '  -P|--partial <dot-partial>  default value: .partial'
			echo '  -E|--ext <dot-ext>          default value get from the directory extension (".bar" for "foo.bar.d")'
			echo '  -i|--startnumber <0-999>    initial number value used in split files name (default: 001)'
			echo '  --raw                       merge will not write the split mark line at all'
			echo '  -<number>|-1|-2|...|-99     the <number> of "-" in the mark (supported range: 0-99)'
			echo '  -1                          the mark line will be "-8<- ... ->8-"'
			echo '  -3                          like the default, the mark value will be "---8<--- ... --->8---"'
			echo '  -0|-00                      no open/close mark shown, only the name'
			echo
			echo 'Samples of use:'
			echo '  '"$0"' --split /etc/file.conf /tmp/test1.conf.d'
			echo '  '"$0"' --prefix '\''# '\'' --partial '\'\'' --ext '\''.conf.disabled'\'' --split /etc/apache2/site-available/foo.conf /tmp/test2.d'

			return 0
		;;
		('-d'|'--dir'|'--merge')	action=merge ;;
		('-f'|'--file'|'--split')	action=split ;;
		('-l'|'--list')		action=list ;;
		('-p'|'--prefix')	shift; prefix="$1";;
		('-s'|'--suffix')	shift; suffix="$1";;
		('-P'|'--partial')	shift; partial="$1";;
		('-E'|'--ext')		shift; ext="$1";;
		('-i'|'--startnumber')	shift;
			case "$1" in
				([0-9]|[0-9][0-9]|[0-9][0-9][0-9])
					startnumber="$1"
				;;
			esac
		;;
		('-1')			n=-;;
		('-2')			n=--;;
		('-3')			n=---;;
		('-00')			n='';;
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
			echo >&2 "Usage: $0 [-p|-s value] -f|-d|-l <input> [<output>]"
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
	if [ -z "$ext" ]; then
		case "$action" in
		("merge")
			ext="${1%/}"
			ext="${ext%.d}"
			ext=".${ext##*.}"
		;;
		("split")
			ext="${1%/}"
			ext=".${ext##*.}"
		;;
		esac
	fi

	case "$action" in
		(merge)	merge_to_file "$@" ;;
		(split)
			if [ -z "$ext" ]; then
				echo >&2 "ERROR: extension is not defined. Please use --ext '.txt'"
				exit 1
			fi
			split_file "$@" ;;
		(list)
			if [ -d "$1" ]; then
				local partialre="$(printf %s "$partial" | string2regexp_grep)"
				ls -1 -- "$1" |
				while read -r f; do
					case "$f" in
					(*.d) ;;
					(*"$ext") ;;
					(*) continue ;;
					esac
					printf %s\\n "$f"
				done |
				decode_slash | sed -e 's,[^.]*\.\([^/]\+\)\.d\(/\),\1\2,g' |
				sed -e 's,[^.]*\.\([^/]\+\)'"$partialre"'$,\1,g' -e 's,[^.]*\.\([^/]\+\)\.d$,\1/,g'
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
