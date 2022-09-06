module Vault::SimpleVault {
    use std::signer;

    use aptos_framework::account;

    //Errors
    const EINVALID_SIGNER: u64 = 0;
    const EADMIN_ALREADY_EXISTS: u64 = 1;

    // Resources
    struct Admin has key {
        resource_account: address
    }

    struct Vault has key {
        pause: bool,
        authority: address
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
        move_to<Vault>(&vault_resource, Vault{pause: true, authority: admin_addr});
    }

    #[test(admin: @Vault)]
    public fun can_init_admin(admin) acquires Admin, Vault {
        
    }
}