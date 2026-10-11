@{
    # "Send feedback": a button at the bottom of the side bar opens a small form, and
    # what the user writes there is sent to the author of the application by e-mail.
    #
    # The application has no mail server and knows no e-mail address. It hands the
    # message to a form service: a web address that accepts a message as JSON over
    # https and passes it on to the mailbox its owner registered there. That keeps the
    # address of the author out of the application and out of this repository.
    #
    # Endpoint: the address of the form at that service. While it is empty the button is
    # not shown at all, so a copy of the project without a form of its own offers
    # nothing that could not work.
    #
    #   Formspree:  Endpoint = 'https://formspree.io/f/<id of the form>'
    #   Web3Forms:  Endpoint = 'https://api.web3forms.com/submit'
    #               Fields   = @{ access_key = '<access key>' }
    #
    # Fields: what the service wants to see in every message besides the text, such as
    # the access key of Web3Forms or a subject line ("_subject" at Formspree, "subject"
    # at Web3Forms). Whatever is written here is public: it is part of the application
    # everybody can read. A key of a form service is made for that; a password is not.
    #
    # What is sent is said in PRIVACY.md and in the form itself: the text, the address
    # the user typed in if any, and the versions of the application and of Windows.

    Endpoint       = ''

    Fields         = @{}

    # The longest text the form accepts, in characters.
    MaximumLength  = 4000

    # How long the application waits for the service to answer.
    TimeoutSeconds = 20
}
