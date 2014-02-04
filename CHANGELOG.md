## 0.5.2 (2014/02/04)

Enhancement:

* Support `log_level` option of Fleuntd v0.10.43

## 0.5.1 (2013/12/28)

Changes

  - No `message` output in the case of `regexpN` or `excludeN` option

## 0.5.0 (2013/12/17)

Features

  - Add `regexpN` and `excludeN` options

## 0.4.2 (2013/12/12)

Features

  - Allow to use `remove_tag_prefix` option alone

## 0.4.1 (2013/11/30)

Features

  - add `remove_tag_prefix` option

## 0.4.0 (2013/11/30)

Changes

  - Change the option name `output_tag` to `tag`. `output_tag` is obsolete.
  - Change the option name `output_with_joined_delimiter` to `delimiter`. `output_with_joined_delimiter` is obsolete.

## 0.3.1 (2013/11/02)

Changes

  - Revert 0.3.0. `string-scrub` gem is only for >= ruby 2.0.

## 0.3.0 (2013/11/02)

Changes

  - Use String#scrub

## 0.2.0 (2013/09/26)

Features

  - less_than, less_equal, greater_than, greater_equal

## 0.1.3 (2013/06/17)

Features

  - comparison

## 0.1.2 (2013/05/16)

Features

  - replace_invalid_sequence

## 0.1.1 (2013/05/05)

Changes:

  - Revert `output_delimiter` to `output_with_joined_delimiter`.

## 0.1.0 (2013/05/05)

Features:

  - aggregate tag/all

Changes:

  - Remove `output_matched_message` option, and make it default. 
  - Rename `output_with_joined_delimiter` to `output_delimiter`. 

Bugfixes:

## 0.0.1

First version
