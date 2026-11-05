# Glossary

Domain language for the POS system. Terms are grounded in the code as it exists;
when code and glossary disagree, the glossary is the decision and the code is
what drifts.

## Sale

A completed checkout. One `orders` document, one receipt number, one cashier, a
snapshot of every line at the price it sold for.

Named **Sale**, not **Order**. The routes, error messages, and tests already say
"sale"; the model class was `Order`. `OrderService` → the Sale module,
`Order` → `Sale`, `OrderItem` → `SaleLine`.

A Sale is not editable. It is either **completed** or **voided**, and voiding is
terminal — there is no reopen and no refund (refund is a payment concern this
system does not model).

## Receipt number

The 7-digit zero-padded number printed on a Sale's receipt, drawn from a single
monotonic counter starting at `1000000` and wrapping at `10000000`.

Sequential on purpose: gaps reveal tampering. Voiding a Sale does **not** return
its number to the counter — the gap is permanent and correct.

## Void

Marking a completed Sale as voided. The document survives as a tombstone; it is
excluded from revenue and it reads as 404 to every caller. Recorded in the
activity log with the acting user and the timestamp.

Cashiers may void their own Sales. Admins may void any.

## Payment

One attempt to be paid by QR: a `payments` document carrying the gateway's
transaction id (`tran_id`), the priced lines the customer was shown, and a
status of `pending`, `scanned`, `paid`, `expired`, `declined` or `failed`.

A Payment is not a Sale. It exists from the moment a code is displayed, and
only `paid` means money moved. The Sale — and its receipt number — is created
when the gateway confirms the code was paid, from the lines stored on the
Payment rather than from a fresh catalogue lookup.

**Confirm** is the transition to `paid` from an open status (`pending` or
`scanned`), and it happens once. The gateway's notification is a hint to go and
look, never evidence: only the read made with this service's own credentials,
agreeing on the amount, may confirm.

**Scanned** is the waiting room between a code on the screen and money in the
till: a payer's banking app has the payment open and has not confirmed it.
Nothing is sold on it, and the QR leaves the display, because a code one phone
is holding must not be shown to the next customer.

## Provider

The gateway a Payment was asked of: `payway` or `cutluy`. It is recorded on the
row, because a payment is settled by the provider that issued it and by no
other, and because it says whose support desk a shop calls when a code did not
work. `PAYMENT_PROVIDER` selects which one the payment routes drive; both sit
behind the same `PaymentProvider` seam and the same three questions — make this
payable, what became of it, what does this delivery refer to.

## Charge amount

What the customer is asked to pay, which is the shop total unless the provider
takes a currency the shop does not price in. CutLuy moves USD only, so a riel
shop's cart is converted line by line at `CUTLUY_KHR_USD_RATE` and rounded to
cents, and the Payment keeps the shop's figure, the customer's figure and the
rate between them. A Sale is booked from the shop's own money; only a
confirmation is checked against the charge.

## Transaction id

`tran_id`: this POS's own identifier for a gateway transaction, at most 20
characters and unique against the merchant's history at the gateway, not merely
against this database. It is how a QR, a notification and a poll all find the
same Payment, and it is what a Sale remembers in `payment_tran_id`. With CutLuy
it doubles as the idempotency key, so a retried request returns the same payment
instead of issuing a second payable code.

## Activity log

The audit trail of who did what, when, and from which client. Currently records
logins only; the Sale module's void transitions extend it.

## Cashier

A user with the cashier role. Sees only their own Sales, and may only void them.

## Admin

A user with the admin role. Sees and may void any Sale.

## Role

A capability a user holds: `1` = Admin, `2` = Cashier. A user's roles are ordered
and the first is their default — the one a freshly issued token carries. Names
live in exactly one place.

## Product

A sellable item: name, code, unit price, optional image, one Product Type, and
an active flag. Inactive Products cannot be added to a cart.

Prices are **snapshotted onto the Sale line** at checkout. A later price change
does not rewrite history.

## Product Type

A category grouping Products — e.g. drinks, food. Names are unique. A type in
use by a Product cannot be deleted.

## Catalogue

The Product Types with their active Products, as the cashier's ordering screen
consumes it. One query, paged — never truncated by a hardcoded limit.

## Platform

Where a Sale originated: `Web`, or whatever the client reports.

## Session

A signed token carrying the user id, the user name, and the default role.
Switching role reissues the token; it does not grant new capabilities.

## Invariant

Worth stating once, in the module that owns it:

- Receipt numbers are unique. Enforced by a unique index, not by a check.
- One gateway transaction produces one Sale. Enforced by the unique partial
  index on `orders.payment_tran_id`, not by a check two confirmations could
  both pass.
- A Sale's `total_price` is always the sum of its lines, rounded to 2 decimals.
- A voided Sale contributes nothing to revenue, ever.