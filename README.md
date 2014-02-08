# fluent-plugin-grepcounter, a plugin for [Fluentd](http://fluentd.org) [![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-grepcounter.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-grepcounter)

Fluentd plugin to count the number of matched messages, and emit if exeeds the `threshold`. 

## Configuration

Assume inputs from another plugin are as belows:

    syslog.host1: {"message":"20.4.01/13T07:02:11.124202 INFO GET /ping" }
    syslog.host1: {"message":"20.4.01/13T07:02:13.232645 WARN POST /auth" }
    syslog.host1: {"message":"20.4.01/13T07:02:21.542145 WARN GET /favicon.ico" }
    syslog.host1: {"message":"20.4.01/13T07:02:43.632145 WARN POST /login" }

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
      "message":["20.4.01/13T07:02:13.232645 WARN POST /auth","20.4.01/13T07:02:43.632145 WARN POST /login"],
      "input_tag":"syslog.host1",
      "input_tag_last":"host1",
    }

### Output message by joining with a delimiter

As default, the `grepcounter` plugin outputs matched `message` as an array as shown above. 
You may want to output `message` as a string, then use `delimiter` option like:

    <match syslog.**>
      type grepcounter
      count_interval 60
      input_key message
      regexp WARN
      exclude favicon.ico
      threshold 1
      add_tag_prefix warn.count
      delimiter \n
    </source>

Then, output bocomes as belows (indented). You can see the `message` field is joined with \n.

    warn.count.syslog.host1: {
      "count":2,
      "message":"20.4.01/13T07:02:13.232645 WARN POST /auth\n20.4.01/13T07:02:43.632145 WARN POST /login",
      "input_tag":"syslog.host1",
      "input_tag_last":"host1",
    }

## Parameters

- count\_interval

    The interval time to count in seconds. Default is 60.

- input\_key *field\_key*

    The target field key to grep out. Use with regexp or exclude. 

- regexp *regexp*

    The filtering regular expression

- exclude *regexp*

    The excluding regular expression like grep -v

- regexp[1-20] *field\_key* *regexp* (experimental)

    The target field key and the filtering regular expression to grep out. No `message` is outputted in this case.

- exclude[1-20] *field_key* *regexp* (experimental)

    The target field key and the excluding regular expression like grep -v. No `message` is outputted in this case.

- threshold

    The threshold number to emit. Emit if `count` value >= specified value.

- greater\_equal

    This is same with `threshold` option. Emit if `count` value is greater than or equal to (>=) specified value. 
    
- greater\_than

    Emit if `count` value is greater than (>) specified value. 
    
- less\_than

    Emit if `count` value is less than (<) specified value. 

- less\_equal

    Emit if `count` value is less than or equal to (<=) specified value. 

- tag

    The output tag. Required for aggregate `all`. 

- add\_tag\_prefix

    Add tag prefix for output message

- remove\_tag\_prefix

    Remove tag prefix for output message

- delimiter

    Output matched messages after `join`ed with the specified delimiter.

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

