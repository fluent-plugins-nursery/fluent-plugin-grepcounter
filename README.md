# fluent-plugin-grepcounter [![Build Status](https://secure.travis-ci.org/sonots/fluent-plugin-grepcounter.png?branch=master)](http://travis-ci.org/sonots/fluent-plugin-grepcounter) [![Dependency Status](https://gemnasium.com/sonots/fluent-plugin-grepcounter.png)](https://gemnasium.com/sonots/fluent-plugin-grepcounter)

## Component

### GrepCounterOutput

Fluentd plugin to count the number of matched messages

## Configuration

## GrepCounterOutput

Assume input from another plugins like belows:

    syslog: {"message":"2013/01/13T07:02:11.124202 INFO GET /ping" }
    syslog: {"message":"2013/01/13T07:02:13.232645 WARN POST /auth" }
    syslog: {"message":"2013/01/13T07:02:14.332145 WARN GET /favicon.ico" }
    syslog: {"message":"2013/01/13T07:02:43.632145 WARN POST /login" }

An example of grepcounter configuration:

    <match syslog>
      type grepcounter
      count_interval 60
      input_key message
      regexp WARN
      exclude favicon.ico
      threshold 1
      add_tag_prefix warn.count
    </source>

Outputs like belows:

    warn.count.syslog: {"count":2,"message":"2013/01/13T07:02:13.232645 WARN POST /auth\n2013/01/13T07:02:43.632145 WARN POST /login"}

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

Copyright (c) 2013 Naotoshi SEO. See [LICENSE](LICENSE) for details.
