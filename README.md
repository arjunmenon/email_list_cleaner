# EmailListCleaner 

EmailListCleaner is a Ruby program that verifies large lists of email addresses stored in CSV files.

## Requirements

- Ruby 2.3.x
- Redis Server
- A publicly reachable IP (a shell account at co-location facility) — OR — SOCKS5 proxy servers
- A CSV list of email addresses (_list.csv)

This program was written to clean a large list of 400k or so addresses because I didn't feel like paying a service to do it, and it seemed like an interesting problem to tackle.

**How It Works**

1. EmailListCleaner loads all addresses into a Redis Set, which removes duplicates.
2. It then utilizes the [email_verifier gem](https://github.com/kamilc/email_verifier), which connects to each SMTP server to verify addresses exist.
3. Finally, it will dump CSV files of "good", "bad", and "todo" (if any remain)

My list was in the format "name", "email" ...so the program expects your `_list.csv` to follow suit.

Check the `scripts` folder for easy to run examples. It's meant for consumption by Ruby devs that know what they're doing. "It worked on my machine", but you might run into issues.


### VERY IMPORTANT - Please note…

Due to the nature of the check, some MX (mail) servers will ban or "blacklist" you from automating this process too quickly from one IP address. The Microsoft family of email addresses in particular (Hotmail.com, MSN.com, Live.com, Outlook.com) are very sensitive to this tactic.

Here's the error message that mx.hotmail.com will return in the above scenario:

> 550 SC-002 Mail rejected by Outlook.com for policy reasons. The mail server IP connecting to Outlook.com has exhibited namespace mining behavior. If you are not an email/network admin please contact your Email/Internet Service Provider for help.

...And an explanation from the Outlook.com website:

> Namespace mining is a method commonly used by malicious senders to generate lists of email addresses. This approach uses automation to sift through possible email names seeking to identify valid email addresses, e.g., Joe@domain.com, John@domain.com, and Josy@domain.com.

I'm unsure of the *EXACT* sleep_time parameter that's necessary - but if you trip their alarms you will need to ditch your current IP. I recommend a cloud provider like [Digital Ocean](https://m.do.co/c/4fba00a6f1fe) or [Linode](https://www.linode.com/?r=641630cf79615a62638a0ccd7504b0f2075f79ec) in this scenario so you can spin down/up instances quickly if you get banned. Keep your Redis instance separate so you don't lose your work each time.

My advice? Either increase the "sleep\_time" parameter in the config.yml file (if you can wait), _or add "proxy\_servers" if you're checking a very large list._Otherwise, you could be waiting days for completion. There are lists of freely available proxies online if you Google, but [Proxy Bonanza](https://proxybonanza.com/en/how_it_works) is another alternative if you want quality.
