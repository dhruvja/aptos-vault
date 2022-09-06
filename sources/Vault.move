module Vault::SimpleVault {
    use std::signer;

    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::managed_coin;

    //Errors
    const EINVALID_SIGNER: u64 = 0;
    const EADMIN_ALREADY_EXISTS: u64 = 1;
    const EVAULTINFO_NOT_CREATED: u64 = 2;
    const EADMIN_NOT_CREATED: u64 = 3;
    const EINVALID_VAULT_INFO_RESOURCE_ACCOUNT: u64 = 4;
    const EDEPOSIT_IS_PAUSED: u64 = 5;
    const EINVALID_AMOUNT: u64 = 6;

    // Resources
    struct Admin has key {
        resource_account: address
    }

    struct VaultInfo has key {
        pause: bool,
        authority: address
    }

    struct Vault has key{
        deposit_amount: u64,
        vault_resource_account: address,
        vault_resource_cap: account::SignerCapability
    }
    
    public entry fun create_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @Vault, EINVALID_SIGNER);
        assert!(!exists<Admin>(admin_addr), EADMIN_ALREADY_EXISTS);

        // Creating a resource account for the vault to store global information like pause status and coin address
        let seed = b"admin";
        let (vault_resource, _vault_resource_signer_cap) = account::create_resource_account(admin, seed);
        let vault_resource_addr = signer::address_of(&vault_resource);
        move_to<Admin>(admin, Admin{resource_account: vault_resource_addr});
        move_to<VaultInfo>(&vault_resource, VaultInfo{pause: true, authority: admin_addr});
    }

    public entry fun deposit<CoinType>(depositor: &signer, vault_info_resource: address, amount: u64) acquires VaultInfo, Vault{
       assert!(exists<VaultInfo>(vault_info_resource), EINVALID_VAULT_INFO_RESOURCE_ACCOUNT); 
       let vault_info = borrow_global<VaultInfo>(vault_info_resource);
       assert!(vault_info.pause == true, EDEPOSIT_IS_PAUSED);
       assert!(exists<Admin>(vault_info.authority), EINVALID_SIGNER);

       let depositor_addr = signer::address_of(depositor); 
       let vault_resource_addr;
       let seed = b"vault";
       if (exists<Vault>(depositor_addr)) {
            let vault = borrow_global<Vault>(depositor_addr);
            vault_resource_addr = vault.vault_resource_account; 
       } else {
            let (vault_resource_account, vault_resource_signer_cap) = account::create_resource_account(depositor, seed);
            managed_coin::register<CoinType>(&vault_resource_account);
            move_to<Vault>(depositor, Vault{deposit_amount: 0, vault_resource_account: vault_info_resource, vault_resource_cap: vault_resource_signer_cap});
            vault_resource_addr = signer::address_of(&vault_resource_account);
            
       };
        let previous_balance = coin::balance<CoinType>(depositor_addr);
        coin::transfer<CoinType>(depositor, vault_resource_addr, amount);
        let after_balance = coin::balance<CoinType>(depositor_addr);
        assert!(previous_balance - after_balance == amount, EINVALID_AMOUNT);
        let vault = borrow_global_mut<Vault>(depositor_addr);
        vault.deposit_amount = vault.deposit_amount + amount;
    }

    // public entry fun withdraw<CoinType>(withdrawer: &signer, vault_info_resource: address, amount: u64) {

    // }

    #[test_only]
    public fun get_resource_account(source: address, seed: vector<u8>): address {
        use std::hash;
        use std::bcs;
        use std::vector;
        use aptos_framework::byte_conversions;
        let bytes = bcs::to_bytes(&source);
        vector::append(&mut bytes, seed);
        let addr = byte_conversions::to_address(hash::sha3_256(bytes));
        addr
    }

    #[test_only]
    struct FakeCoin {}

    #[test(admin = @Vault)]
    public fun can_init_admin(admin: signer)  {
        create_admin(&admin);
        let admin_addr = signer::address_of(&admin);
        assert!(exists<Admin>(admin_addr), EADMIN_NOT_CREATED);

        let seed = b"admin";
        let vault_resource_addr = get_resource_account(admin_addr, seed);
        assert!(exists<VaultInfo>(vault_resource_addr), EVAULTINFO_NOT_CREATED);
    }

    #[test(admin = @0x2)]
    #[expected_failure(abort_code = 0)]
    public fun others_cannot_create_admin_account(admin: signer) {
        // only the account who has published the module can create an admin.
        create_admin(&admin);
    }

    #[test(admin = @Vault, depositor= @0x2)]
    public fun user_can_deposit(admin: signer, depositor: signer) acquires VaultInfo, Vault {
        use aptos_framework::aptos_account;

        create_admin(&admin);
        let admin_addr = signer::address_of(&admin);
        let admin_seed = b"admin";
        let vault_resource_addr = get_resource_account(admin_addr, admin_seed); 
        let depositor_addr = signer::address_of(&depositor);
        let initial_mint_amount = 10000;

        managed_coin::initialize<FakeCoin>(&admin, b"fake", b"F", 9, false);
        aptos_account::create_account(depositor_addr);
        managed_coin::register<FakeCoin>(&depositor);
        managed_coin::mint<FakeCoin>(&admin, depositor_addr, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(depositor_addr) == initial_mint_amount, EINVALID_AMOUNT);

        let initial_deposit = 100;
        deposit<FakeCoin>(&depositor, vault_resource_addr, initial_deposit);
        let vault_seed = b"vault";
        let vault_addr = get_resource_account(depositor_addr, vault_seed);
        assert!(coin::balance<FakeCoin>(depositor_addr) == initial_mint_amount - initial_deposit, EINVALID_AMOUNT);
        assert!(coin::balance<FakeCoin>(vault_addr) == initial_deposit, EINVALID_AMOUNT);
    }


}