# fluent-plugin-grepcounter [![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-grepcounter.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-grepcounter) [![Dependency Status](https://gemnasium.com/sonots/fluent-plugin-grepcounter.png)](https://gemnasium.com/sonots/fluent-plugin-grepcounter) [![Coverage Status](https://coveralls.io/repos/sonots/fluent-plugin-grepcounter/badge.png?branch=master)](https://coveralls.io/r/sonots/fluent-plugin-grepcounter)

Fluentd plugin to count the number of matched messages.

## Configuration

Assume inputs from another plugin are as belows:

    syslog.host1: {"message":"2013/01/13T07:02:11.124202 INFO GET /ping" }
    syslog.host1: {"message":"2013/01/13T07:02:13.232645 WARN POST /auth" }
    syslog.host1: {"message":"2013/01/13T07:02:21.542145 WARN GET /favicon.ico" }
    syslog.host1: {"message":"2013/01/13T07:02:43.632145 WARN POST /login" }

An example of grepcounter configuration:

    <match syslog.**>
      type grepcounter
      count_interval 60
      input_key message
      regexp WARN
      exclude favicon.ico
      threshold 1
      add_tag_prefix warn.count
    </source>

Then, output bocomes as belows (indented):

    warn.count.syslog.host1: {
      "count":2,
      "message":["2013/01/13T07:02:13.232645 WARN POST /auth","2013/01/13T07:02:43.632145 WARN POST /login"],
      "input_tag":"syslog.host1",
      "input_tag_last":"host1",
    }

Another example of grepcounter configuration to use `output_with_joined_delimiter`:

    <match syslog.**>
      type grepcounter
      count_interval 60
      input_key message
      regexp WARN
      exclude favicon.ico
      threshold 1
      add_tag_prefix warn.count
      output_with_joined_delimiter \n
    </source>

Then, output bocomes as belows (indented). You can see the `message` field is joined with \n.

    warn.count.syslog.host1: {
      "count":2,
      "message":"2013/01/13T07:02:13.232645 WARN POST /auth\n2013/01/13T07:02:43.632145 WARN POST /login",
      "input_tag":"syslog.host1",
      "input_tag_last":"host1",
    }

## Parameters

- count\_interval

    The interval time to count in seconds. Default is 60.

- input\_key

    The target field key to grep out

- regexp

    The filtering regular expression

- exclude

    The excluding regular expression like grep -v

- threshold

    The threshold number to emit

- comparator

    The comparation operator for the threshold (either of `>=` or `<=`). Default is `>=`, i.e., emit if count >= threshold. 
    NOTE: 0 count message will not be emitted even if `<=` is specified because standby nodes receive no message usually.

- output\_with\_joined\_delimiter

    Join the output message array field with the specified delimiter to make the output message be a string. 

- aggregate

    Count by each `tag` or `all`. The default value is `tag`. 

- output\_tag

    The output tag. Required for aggregate `all`. 

- add\_tag\_prefix

    Add tag prefix for output message

- replace\_invalid\_sequence

    Replace invalid byte sequence in UTF-8 with '?' character if `true`

- store\_file

    Store internal count data into a file of the given path on shutdown, and load on statring. 

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2013 Naotoshi SEO. See [LICENSE](LICENSE) for details.

