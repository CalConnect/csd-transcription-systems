#!/usr/bin/env bash

for file in index.html documents.xml
do
  outdir=site test_existence_of_file "${file}"
done

for file in {cc,iso}-24229.{html,pdf,doc}
do
  test_existence_of_file "${file}"
done

test_file_type iso-24229.pdf PDF
test_file_type cc-24229.pdf PDF

test_existence_of_auth_id ALA-LC
test_existence_of_auth_id BGN-PCGN
test_existence_of_auth_name 'American Library Association'
test_existence_of_auth_name 'United Nations'
test_existence_of !alalc
test_existence_of !bgnpcgn

for name in "List Paragraph" "Heading 1" "Heading 2" "Heading 3" "Heading 4" "Heading 5" "Heading 6" "TOC 1" "TOC 2" "TOC 3" "Footnote Reference"
do
  test_existence_of 'mso-style-name: "'"${name}"'"' 'human-readable style names in English' site/documents/iso-24229.doc

done
