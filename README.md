# datasift-ruby-utils

This repository is a collection of tools meant to augment the base DataSift client libraries. Many of the tools here were developed for a specific purpose and are independent of the support and attention to detail afforded both to (a) the primary client libraries and (b) certaintly the broader DataSift platform.

These tools are not actively maintained, but we hope you find them useful, if not in the code, then in the ideas and approaches they illustrate. Give us a shout if you make an improvement that should be shared with the commmunity--we really appreciate it!

## Getting Started

At present, there are only a couple of tools included in the repository, and each is described in detail below. These, and all tools to be included here, are written in Ruby and therefore require the Ruby interpreter. You can obtain the interpreter from the official [Ruby Language website](https://www.ruby-lang.org/en/documentation/installation/), or via a package manager of your choice. For best results, we recommend at least Ruby 2.2.x or higher. Tools have been tested against Ruby 2.3.0 and 2.3.1.

Once Ruby is installed, clone the git repository:

    $ git clone https://github.com/jontec/datasift-ruby-utils
  
Next, to install the dependencies, either use the following command for Ruby gems, or use bundler to install:

    $ gem install datasift activesupport terminal-table

OR

    $ cd datasift-ruby-utils
    $ bundle install

## Tools

### AccountSelector

AccountSelector is a class that is used to manage API keys for DataSift PYLON accounts. It's not easy for most humans to memorize API keys, so instead you do the following:

1. Create an identities.yml file containing all of your access details (see identities.yml.sample). Give your identities and indexes meaningful, memorable names in this file.
2. Use AccountSelector.select to select your account (usually via :default) and then your respective identities. Store the config (username and API key) in a variable
3. Invoke DataSift::Pylon.new() with the variable containing your "config" as the only argument.
4. Enjoy hassle-free coding (for development only, of course) when working with your PYLON identities. Use :with_indexes, :with_tokens, or :with_billing_date along with a second recieving variable to access other data stores inside your identities file.

#### Example Usage

```ruby

require_relative 'account_selector' # you may need to use /path/to/account_selector.rb 

# select the account API key from your default account
config = AccountSelector.select :default

# select a named identity from your default account
config = AccountSelector.select :default, :primary

# select a named identity and its indexes from your default account
config, options = AccountSelector.select :default, :primary, with_indexes: true

```

### usage_reporter.rb

This script provides a handy approximation of your current interaction consumption against your monthly allowance. Because it uses the API (therefore subject to redaction) and many other platform limitations, it is not an exact accounting of your consumption. However, for users with primarily medium and large-sized indexes (i.e. greater than 50-100k interactions), results should be rather close.

#### Usage

You can invoke the usage reporter in one of two ways, either with no arguments or with two to three including your account username, account API key, and optionally, the first day of your billing period:

    $ ruby usage_reporter.rb

OR
 
    $ ruby usage_reporter.rb jontec <api key> 15

When invoked with no arguments, the usage reporter will use AccountSelector to populate these values from your identities.yml file. If a billing start date is not specified in either case, it will default to using the 1st of the month.

NOTE: If you manually specify the API key, please ensure that this is the *account* API key, not the API key for your master identity.

#### How it Works

Using the inputs described, the usage reporter executes the following 5 high-level tasks described below. We want this script to be a utility as much as a reference for volume management, so we've documented the steps in detail.

A key design goal was to minimize the number of queries required to ensure that this pattern would work for any customer (including those with 100s of identities and/or indexes per month).

1. **Determine the relevant date representing the start of your billing analysis.**
  
  Using Ruby Date functions, we identify a date representing the proper first date of consumption in the current billing period. This is important because, for example, February 31st never exists. So, if the first day of your billing period was the 31st, we'd actually want it to start on February 29th or 28th depending on the year. Importantly, there's also a time object associated with this start date, aligned with PST (GMT -08:00), invariant according to DST and therefore consistent with DataSift's platform system time.

2. **Use your account API key to list all indexes associated with your account.** Then, using the computed date, identify which indexes collected volume in this billing period and which indexes ONLY collected volume within the current billing period.

  The /get endpoint already provides a lot of great information about your indexes, including their names, the ID of their identity, and of course a summary volume if they've collected interactions for 1,000 or more unique authors. Therefore, if an index was created in the current billing period, we get its contribution to your total volume for free.
  
  However, some indexes won't matter at all (they started and stopped before the start of the current period) while others will have a partial volume contributing to the current billing period (they were collected before the current period started). To calculate the partial contribution, we must issue analysis queries that allow us to identify how much volume these indexes collected.
  
  Analysis queries require that we authenticate using the API key and identity that the index belongs to. Therefore, we cache the identity IDs for all indexes at this step and also store the indexes according to their identities to simplify future analyses.

3. **Use your account API key to list all the identities associated with your account.**

  The GET /account/identity endpoint provides information on all identities for your account, including their id, label, and API key. Iterating over each of the identities in turn, we can look up the associated indexes (in groups, by identity id) and use prior judgements to qualify them for analysis. For those that require it, we now have the API key and can issue the analysis query to identify volume only associated with this billing period.
	
4. **Issue analysis queries (if necessary) to identify volume associated with this billing period.**

	If there are recordings that started before the billing period, one analysis query each is issued. The query is a timeseries analysis by day (to minimize redaction), with the start explictly set to the billing start date (and time with zone). Because the entirety of the analysis is relevant, we can use just the total to attribute volume. It's easy to imagine also collecting the detailed results of this analysis to identify spikes.
	
	In certain cases, either because the index has zero or very low volumes, in the current period or overall, the analysis results will be redacted. In this case, the usage reporter returns a count of redacted indexes to assist in developing a level of confidence about its results. That is, the more analysis results that are redacted, the greater the chance that the final total may be off by up to 1,000 or more records per redacted query.
	
	Also, it's important to note that the usage reporter does not behave differently when redaction occurs within a result set. For example, if there were just under 100 interactions on 5 days out of 15 within the current period for an index, these five days will not be included in the result and the interaction count for the index could be off by nearly 500. As a design consideration (and limitation), it was determined that it's impossible to differentiate between indexes experiencing redaction in this way and those that were stopped and started intentionally by users.

5. **Report the total volume and report on each index, with identity details.**

	Finally, once all results have been tabulated, we report the overall total that has been summed continuously throughout the script. In addition, we have also been building a hash with volume as the key, and by iterating over these in reverse sort order, we can output a listing of the recordings in descending order by volume. Also, since we cached the identity details in step 3, we can report the identity associated with each index as well.

#### Example Output

The usage reporter provides informational output at each major step as shown below. A notice regarding how many points/credits consumed are provided (in the future, we may by default require you to confirm before continuing). 

```
$ ruby usage_reporter.rb
[Start] Calculating consumption for the billing period beginning on 2016-09-01
[Done] Index identification complete.
  * Found 11 indexes, 6 of which require analysis.
	  This will consume 150 points from your hourly PYLON /analyze API limit.
  * Indexes first created in this billing period represent 155,300 interactions.
[Start] Fetching identity information
[Working] Executing analysis queries (6 total): 1 2 3 4 5 6 100%
[Done] Analyzed target indexes. 0 indexes were redacted.
  * The final volume count is: 10,106,600 interactions.

Usage Summary:
+-----------+--------------------+-------------+---------------------------+
| User Name | Billing Start Date | Total Usage | Generated At              |
+-----------+--------------------+-------------+---------------------------+
| myuser    | 2016-09-01         | 10,106,600  | 2016-09-14 08:03:02 -0800 |
+-----------+--------------------+-------------+---------------------------+

Usage Totals by Index:
+-----------+---------+---------------------------+----------+------------------------------------------+
| Volume    | Status  | Index Name                | Identity | Index ID                                 |
+-----------+---------+---------------------------+----------+------------------------------------------+
| 9,167,800 | running | Brand Analysis            | myident  | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa         |
|   449,300 | running | Category-wide Recording   | Category | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb |
|   140,300 | running | Rewards Program           | myident  | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1         |
|   114,700 | running | Brand Strategy A          | BrandA   | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb1 |
|    74,000 | stopped | IndexB v4                 | myident  | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2 |
|    73,900 | stopped | IndexB v3                 | myident  | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb3 |
|    53,400 | running | Sample Demo               | BrandB   | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb4 |
|    25,800 | running | Content Discovery         | sampling | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb5 |
|     7,400 | running | Analytics                 | CustB    | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb6 |
|         0 | running | IndexB v2                 | myident  | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb7 |
|         0 | running | Cool                      | myident  | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa2         |
+-----------+---------+---------------------------+----------+------------------------------------------+

Disclaimer: These totals are approximations only and may not accurately represent interaction totals
  for official billing purposes.
```
