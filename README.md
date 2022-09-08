# aptos-vault
A module where users can deposit and withdraw their funds having an adminstrator who can pause and unpause the deposits and withdrawals.

A user can deposit and withdraw any number of coins ( cannot withdraw more than deposit ofc ). 
These are the functions which an user can call
- deposit: To deposit the coin, by specifying the coin type and amount
- withdraw: To withdraw the coin, by specifying the coin type and amount

An admin can pause or unpause the new deposits and withdrawals. If the admin pauses, then no user can withdraw their already deposited funds or deposit new funds.
