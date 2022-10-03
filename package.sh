#!/usr/bin/sh
version_tag=$1
git archive --prefix se-ltn-glue/ -o se-ltn-glue_${version_tag}.zip ${version_tag}

