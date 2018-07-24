#!/bin/bash
#
# create_makefile.sh: semantic dependency graph for LilyPond projects
#
# Usage:
#   ./create_makefile.sh
#   make
#
# Originally written by William Chargin <wchargin@gmail.com>. Released
# under the MIT License.

# Globally disable the following warning (requires shellcheck>=0.4.6),
# which complains about single-quoted strings with dollar signs, in case
# you thought that some expansion would take place. But we use this
# pattern frequently to output Make rules, like '$(RM) foo', so we
# disable this warning.
# shellcheck disable=SC2016

set -eu

# Identify non-transitive dependencies of LilyPond file $1 by analyzing
# the document structure. Output is a NUL-delimited stream of filenames.
deps() {
    # shellcheck disable=SC2094
    <"$1" tr '\n' '\0' |
        sed -zne 's/.*\\include "\([^"]\+\)".*/\1/p' | \
        zawk -v base="$(dirname "$1")" '{ print base "/" $0 }' | \
        # Some dependencies may library files, like `articulate.ly`,
        # which are not stored in the local file tree. Therefore, if a
        # dependency does not exist locally, we assume that it is a
        # library and don't track it in the dependency graph.
        filter_existing | \
        sed -z 's:/[^/]\+/../:/:g' | \
        lydep_names | \
        sort -zu
}

# Print the lydep file associated with each input file. For instance,
# `foo.ly` becomes `.foo.ly.lydep`. Input and output are NUL-delimited
# streams of filenames.
lydep_names() {
    zawk -v FS="/" -v OFS="/" '{ $NF = "." $NF ".lydep"; print }'
}

# Print out each specified file, if it exists. Input and output are
# NUL-delimited streams of filenames.
filter_existing() {
    while read -r -d $'\0' filename; do
        if [ -f "${filename}" ]; then
            printf '%s\0' "${filename}"
        fi
    done
}

# Like awk(1), but with NUL-delimited records (both input and output).
zawk() {
    awk -v RS='\0' -v ORS='\0' "$@"
}

# Print the lydep file associated with the input file $1.
lydep_name() {
    printf '%s\0' "$1" | lydep_names | tr -d '\0'
}

# Emit a Make rule for the lydep file associated with the LilyPond file
# specified in $1.
ly_rule() {
    filename="$1"
    printf '.SECONDARY: %s\n' "$(lydep_name "${filename}")"
    printf '%s: \\\n\t\t%s' "$(lydep_name "${filename}")" "${filename}"
    deps "${filename}" | while read -r -d $'\0' dep; do
        printf ' \\\n\t\t%s' "${dep}"
    done
    printf '\n'
}

# Emit Make rules for all lydep files.
ly_depgraph() {
    find . \( -name '*.ly' -o -name '*.ily' \) -print0 | sort -z | \
        while read -r -d $'\0' filename; do
            ly_rule "${filename}"
        done
}

# Emit a Make rule indicating that output $1 can be created by running
# LilyPond on $2, with appropriate transitive dependencies.
ly_entry_point() {
    printf '%s: %s\n' "$1" "$(lydep_name "$2")"
    printf '\t$(LY) %s\n' "$2"
}

# Emit the main Makefile.
makefile() {
    main=MozartWA-KV488.ly
    movements=( *-movement-*.ly )
    parts=( *-part-*.ly )
    midis=( *-midi-*.ly )

    printf '# AUTOGENERATED MAKEFILE --- DO NOT EDIT\n'
    printf '# Run "%s" to regenerate\n' "$(basename "$0")"
    printf '\n'

    printf 'LY ?= lilypond -dno-point-and-click $(LYFLAGS)\n'
    printf 'ifdef PAPERSIZE\n'
    printf '\tLYFLAGS += -dpaper-size=%s\n' '\"$(PAPERSIZE)\"'
    printf 'endif\n'
    printf '\n'

    printf '# Metatargets, for convenience\n'
    printf '.PHONY: all main movements parts midi\n'
    printf '.PHONY: quicktest test quickcheck check clean\n'
    printf 'all: main movements parts midi\n'
    printf 'main: %s\n' "${main%.ly}.pdf"
    printf 'movements:'
    printf ' \\\n\t\t%s.pdf' "${movements[@]%.ly}"
    printf '\n'
    printf 'parts:'
    printf ' \\\n\t\t%s.pdf' "${parts[@]%.ly}"
    printf '\n'
    printf 'midi:'
    printf ' \\\n\t\t%s.midi' "${midis[@]%.ly}"
    printf '\n'
    printf 'quicktest quickcheck:\n'
    printf '\t%s\n' ./assert_barchecks.sh
    printf '\t%s\n' ./assert_consistent_marks.sh
    printf 'test check: quicktest\n'
    printf \
        '\t! $(MAKE) all -B PAPERSIZE=%s 2>&1 | grep -F -e err -e warn >&2\n' \
        a4 letter
    printf 'clean:\n'
    printf '\t$(RM) "%s"\n' "${main%.ly}.pdf"
    printf '\t$(RM) "%s.pdf"\n' "${movements[@]%.ly}"
    printf '\t$(RM) "%s.pdf"\n' "${parts[@]%.ly}"
    printf '\t$(RM) "%s.midi"\n' "${midis[@]%.ly}"
    printf '\n'

    printf '# LilyPond entry points\n'
    for file in "${main}" "${movements[@]}" "${parts[@]}"; do
        ly_entry_point "${file%.ly}.pdf" "${file}"
    done
    for file in "${midis[@]}"; do
        ly_entry_point "${file%.ly}.midi" "${file}"
    done

    printf '\n'
    printf '# LilyPond dependency graph\n'
    ly_depgraph
}

cd "$(dirname "$(readlink -f "$0")")"
makefile >Makefile
