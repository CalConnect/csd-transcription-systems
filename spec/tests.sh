#!/usr/bin/env bash

for file in index.html documents.xml
do
  outdir=site test_existence_of_file "${file}"
done

test_existence_of_auth_code sfs
test_existence_of_auth_name 'Office of the Royal Society'
test_existence_of_auth_remark 'Formerly named The Royal Institute of Thailand'
for file in {cc,iso}-24229.{html,pdf,doc}
do
  test_existence_of_file "${file}"
done
