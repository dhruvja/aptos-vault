module Vault::SimpleVault {
    use std::signer;
    use std::bcs;
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;

    use aptos_std::type_info;
    
    //Errors
    const EINVALID_SIGNER: u64 = 0;
    const EADMIN_ALREADY_EXISTS: u64 = 1;
    const EADMIN_NOT_CREATED: u64 = 3;
    const EINVALID_ADMIN_ACCOUNT: u64 = 4;
    const EDEPOSIT_IS_PAUSED: u64 = 5;
    const EINVALID_AMOUNT: u64 = 6;
    const EVAULT_NOT_CREATED: u64 = 7;
    const ELOW_BALANCE: u64 = 8;
    const EALREADY_PAUSED: u64 = 9;
    const EALREADY_UNPAUSED: u64 = 10;
    const EWITHDRAWAL_IS_PAUSED: u64 = 11;

    // Resources
    struct Admin has key {
        pause: bool
    }

    struct Vault has key{
        deposit_amount: u64,
        vault_resource_account: address,
        vault_resource_cap: account::SignerCapability,
        coin_address: address
    }
    
    public entry fun create_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        /// The @Vault is the address of the account publishing the module. So this can be called only once
        assert!(admin_addr == @Vault, EINVALID_SIGNER);
        assert!(!exists<Admin>(admin_addr), EADMIN_ALREADY_EXISTS);

        move_to<Admin>(admin, Admin{pause: false});
    }

    public entry fun deposit<CoinType>(depositor: &signer, vault_info_resource: address, vault_resource: address,amount: u64) acquires Admin, Vault{
       assert!(exists<Admin>(vault_info_resource), EINVALID_ADMIN_ACCOUNT); 
       let vault_info = borrow_global<Admin>(vault_info_resource);
       assert!(vault_info.pause == false, EDEPOSIT_IS_PAUSED);

       /// Getting the address of the coin deposited
       let type_info = type_info::type_of<CoinType>();
       let addr = type_info::account_address(&type_info);
       let bytes = bcs::to_bytes(&addr);

       let depositor_addr = signer::address_of(depositor); 
       let seed = b"vault";
       // appending the seeds with the address of a coin so it remains unique for a particular user
       vector::append(&mut bytes, seed);
    
       if (!exists<Vault>(vault_resource)) {
            /// A resource account is created for every different type of coin deposit. So a user can now deposit any coin of any amount.
            let (vault_resource_account, vault_resource_signer_cap) = account::create_resource_account(depositor, bytes);
            managed_coin::register<CoinType>(&vault_resource_account);
            vault_resource = signer::address_of(&vault_resource_account);
            move_to<Vault>(&vault_resource_account, Vault{deposit_amount: 0, vault_resource_account: vault_resource, vault_resource_cap: vault_resource_signer_cap, coin_address: addr});
       };
        let previous_balance = coin::balance<CoinType>(depositor_addr);
        coin::transfer<CoinType>(depositor, vault_resource, amount);
        let after_balance = coin::balance<CoinType>(depositor_addr);
        assert!(previous_balance - after_balance == amount, EINVALID_AMOUNT);
        let vault = borrow_global_mut<Vault>(vault_resource);
        vault.deposit_amount = vault.deposit_amount + amount;
    }

    public entry fun withdraw<CoinType>(withdrawer: &signer, vault_info_resource: address, vault_resource: address, amount: u64) acquires Vault, Admin {
       assert!(exists<Admin>(vault_info_resource), EINVALID_ADMIN_ACCOUNT); 
       let vault_info = borrow_global<Admin>(vault_info_resource);
       assert!(vault_info.pause == false, EWITHDRAWAL_IS_PAUSED);
       let withdrawer_addr = signer::address_of(withdrawer);
       assert!(exists<Vault>(vault_resource), EVAULT_NOT_CREATED);

       let vault = borrow_global_mut<Vault>(vault_resource);
       assert!(coin::balance<CoinType>(vault_resource) >= amount, ELOW_BALANCE);
       assert!(vault.deposit_amount >= amount, ELOW_BALANCE);

       let vault_resource_signer = account::create_signer_with_capability(&vault.vault_resource_cap);
       coin::transfer<CoinType>(&vault_resource_signer, withdrawer_addr, amount);
       vault.deposit_amount = vault.deposit_amount - amount;
    }

    public entry fun pause(admin: &signer) acquires Admin {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Admin>(admin_addr), EINVALID_ADMIN_ACCOUNT);  
        let vault_info = borrow_global_mut<Admin>(admin_addr);
        assert!(!vault_info.pause, EALREADY_PAUSED);

        vault_info.pause = true;
    }

    public entry fun unpause(admin: &signer) acquires Admin {
        let admin_addr = signer::address_of(admin);
        assert!(exists<Admin>(admin_addr), EINVALID_ADMIN_ACCOUNT);  
        let vault_info = borrow_global_mut<Admin>(admin_addr);
        assert!(vault_info.pause, EALREADY_UNPAUSED);

        vault_info.pause = false;
    }

    #[test_only]
    public fun get_resource_account(source: address, seed: vector<u8>)  : address {
        use std::hash;
        use aptos_std::from_bcs;
        let bytes = bcs::to_bytes(&source);
        vector::append(&mut bytes, seed);
        from_bcs::to_address(hash::sha3_256(bytes))
    }
    #[test_only]
    public fun initialize_coin_and_mint(admin: &signer, user: &signer, mint_amount: u64) {
        use aptos_framework::aptos_account;
        let user_addr = signer::address_of(user);
        managed_coin::initialize<FakeCoin>(admin, b"fake", b"F", 9, false);
        aptos_account::create_account(user_addr);
        managed_coin::register<FakeCoin>(user);
        managed_coin::mint<FakeCoin>(admin, user_addr, mint_amount); 
    }
    #[test_only]
    public fun return_mint_amounts(): (u64, u64) {
        let initial_mint_amount = 10000;
        let initial_deposit = 100;
        return (initial_mint_amount , initial_deposit)
    }

    #[test_only]
    struct FakeCoin {}

    #[test(admin = @Vault)]
    public fun can_init_admin(admin: signer)  {
        create_admin(&admin);
        let admin_addr = signer::address_of(&admin);
        assert!(exists<Admin>(admin_addr), EADMIN_NOT_CREATED);

    }

    #[test(admin = @0x4)]
    #[expected_failure(abort_code = 0)]
    public fun others_cannot_create_admin_account(admin: signer) {
        // only the account who has published the module can create an admin.
        create_admin(&admin);
    }

    #[test(admin = @Vault, user= @0x2)]
    public fun end_to_end(admin: signer, user: signer) acquires Vault, Admin {
        create_admin(&admin);
        let user_addr = signer::address_of(&user);
        let admin_addr = signer::address_of(&admin);
       
        let (initial_mint_amount, initial_deposit) = return_mint_amounts();

        initialize_coin_and_mint(&admin, &user, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount, EINVALID_AMOUNT);

        /// since this is our first deposit, we are passing a dummy address now ( admin_addr )
        /// A new resource account would be created when the resource account passed is not created.
        /// The third parameter can be anything when it our first deposit.
        deposit<FakeCoin>(&user, admin_addr, admin_addr , initial_deposit);

        /// The below code is to derive the seeds which is a combination of seed + coin_address along with source address
        let vault_seed = b"vault";
        let type_info = type_info::type_of<FakeCoin>();
        let addr = type_info::account_address(&type_info);
        let bytes = bcs::to_bytes(&addr);
        vector::append(&mut bytes, vault_seed);
        
        let vault_addr = get_resource_account(user_addr, bytes);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount - initial_deposit, EINVALID_AMOUNT);
        assert!(coin::balance<FakeCoin>(vault_addr) == initial_deposit, EINVALID_AMOUNT);

        // Since the withdrawals and deposits are not paused, the user can withdraw their deposit

        // Withdrawing the deposited amount
        withdraw<FakeCoin>(&user, admin_addr, vault_addr , initial_deposit);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount, EINVALID_AMOUNT);
        assert!(coin::balance<FakeCoin>(vault_addr) == 0, EINVALID_AMOUNT);

    }

    #[test(admin = @Vault, user = @0x2)]
    #[expected_failure(abort_code = 11)]
    public fun cannot_withdraw_after_pause(admin: signer, user: signer) acquires Admin, Vault {
        create_admin(&admin);
        let user_addr = signer::address_of(&user);
        let admin_addr = signer::address_of(&admin);
       
        let (initial_mint_amount, initial_deposit) = return_mint_amounts();

        initialize_coin_and_mint(&admin, &user, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount, EINVALID_AMOUNT);

        deposit<FakeCoin>(&user, admin_addr, admin_addr , initial_deposit);

        let vault_seed = b"vault";
        let type_info = type_info::type_of<FakeCoin>();
        let addr = type_info::account_address(&type_info);
        let bytes = bcs::to_bytes(&addr);
        vector::append(&mut bytes, vault_seed);

        let vault_addr = get_resource_account(user_addr, bytes);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount - initial_deposit, EINVALID_AMOUNT);
        assert!(coin::balance<FakeCoin>(vault_addr) == initial_deposit, EINVALID_AMOUNT);

        pause(&admin);
        withdraw<FakeCoin>(&user, admin_addr, vault_addr, initial_deposit); 

        /// Since the deposits and the withdrawals are paused, any new actions (deposits/withdrawals) would throw an error. 
        /// In our case we should get an error with abort code 11
    }

    #[test(admin= @Vault, user = @0x2)]
    #[expected_failure(abort_code = 5)]
    public fun cannot_deposit_after_pause(admin: signer, user: signer) acquires Admin, Vault {
        create_admin(&admin);
        let user_addr = signer::address_of(&user);
        let admin_addr = signer::address_of(&admin);
       
        let (initial_mint_amount, initial_deposit) = return_mint_amounts();

        initialize_coin_and_mint(&admin, &user, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(user_addr) == initial_mint_amount, EINVALID_AMOUNT); 

        // Pausing before depositing
        pause(&admin);

        // any deposit or withdrawal after this wont happen 
        deposit<FakeCoin>(&user, admin_addr, admin_addr, initial_deposit);

        /// Since the deposits/withdrawals are paused, the program should abort with code 5 ( since we are depositing )
    }


}