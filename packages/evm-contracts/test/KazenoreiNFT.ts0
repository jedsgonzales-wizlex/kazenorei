import assert from "node:assert/strict";
import { before, after, describe, it } from "node:test";

import { expect } from "chai";
import { network } from "hardhat";
import { ethers } from "ethers";

const nftName = "KazenoreiNFT";
const nftSymbol = "KNFT";
const nftUri = "https://example.com/metadata/";

const ZeroAddress = ethers.ZeroAddress as `0x${string}`;

describe("KazenoreiNFT", async function () {
    const { viem, provider } = await network.connect();
    const publicClient = await viem.getPublicClient();
    const [senderClient, nftOwner1, inheritor1, nftOwner2, inheritor2] = await viem.getWalletClients();

    let contract: Awaited<ReturnType<typeof viem.deployContract<"KazenoreiNFT">>>;
    let tokenId: bigint = 1n; // Initialize tokenId

    const createId = () => tokenId++;

    before(async () => {
        contract = await viem.deployContract("KazenoreiNFT");
    });
    
    describe("Deployment", async () => {
        it('should initialize with assigned name, symbol', async () => {
            await contract.write.initialize([nftName, nftSymbol, nftUri]);

            assert.equal(await contract.read.name(), nftName);
            assert.equal(await contract.read.symbol(), nftSymbol);
        });
    });

    describe("On Mintable", async () => {
        const id = createId();

        it('should not allow minting to zero address', async () => {
            
            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.mint([ZeroAddress, id, ""]),
                contract, "ERC721InvalidReceiver", [ZeroAddress]);
        });

        it('should not allow unauthorized minting', async () => {
            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.mint([ZeroAddress, id, ""], { account: nftOwner1.account }),
                contract, "OwnableUnauthorizedAccount", [ethers.getAddress(nftOwner1.account.address)]);
        });

        it('should allow minting of NFTs', async () => {
            // mint 1 nft
            await contract.write.mint([senderClient.account.address, id, ""]);
            const owner = await contract.read.ownerOf([id]);

            expect(owner.toLowerCase()).to.equal(senderClient.account.address.toLowerCase());
        });

        it('should have correct base URI', async () => {
            const tokenUri = await contract.read.tokenURI([id]);

            expect(tokenUri).to.equal(nftUri + id.toString());
        });
    });

    describe("On Burnable", async () => {
        it('should allow token owner burning of NFTs', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);
            await contract.write.burn([id], { account: nftOwner1.account });

            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.read.ownerOf([id]),
                contract, "ERC721NonexistentToken", [id]);
        });

        it('should disallow non-token owner burning of NFTs', async () => {
            const id = createId();
            await contract.write.mint([nftOwner2.account.address, id, ""]);
            
            await viem.assertions.revertWith(
                contract.write.burn([id]),
                "UNAUTHORIZED_BURN_ERROR");
        });
    });

    describe("On Transferring", async () => {
        it('should allow token owner transferring of NFTs', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);
            await contract.write.transferFrom([nftOwner1.account.address, nftOwner2.account.address, id], { account: nftOwner1.account });

            const newOwner = await contract.read.ownerOf([id]);
            expect(newOwner.toLowerCase()).to.equal(nftOwner2.account.address.toLowerCase());
        });

        it('should allow token owner safe transferring of NFTs', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);
            await contract.write.safeTransferFrom([nftOwner1.account.address, nftOwner2.account.address, id], { account: nftOwner1.account });

            const newOwner = await contract.read.ownerOf([id]);
            expect(newOwner.toLowerCase()).to.equal(nftOwner2.account.address.toLowerCase());
        });

        it('should not allow others from transferring someone\'s NFTs', async () => {
            const id1 = createId();
            const id2 = createId();

            await contract.write.mint([nftOwner1.account.address, id1, ""]);
            await contract.write.mint([nftOwner2.account.address, id2, ""]);

            // Try sending nftOwner2's NFT to nftOwner1 using nftOwner1's account

            /** Openzeppelin logic in this is wrong. */
            /* await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.transferFrom([nftOwner1.account.address, nftOwner1.account.address, id2], { account: nftOwner1.account }),
                contract, "ERC721IncorrectOwner", [ethers.getAddress(nftOwner1.account.address), id2, ethers.getAddress(nftOwner2.account.address)]
            ); */

            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.transferFrom([nftOwner1.account.address, nftOwner2.account.address, id2], { account: nftOwner1.account }),
                contract, "ERC721InsufficientApproval", [ethers.getAddress(nftOwner1.account.address), id2]
            );
        });

        it('should not allow others from transferring someone\'s NFTs if not approved', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);

            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.transferFrom([nftOwner1.account.address, nftOwner2.account.address, id], { account: senderClient.account }),
                contract, "ERC721InsufficientApproval", [ethers.getAddress(senderClient.account.address), id]
            );
        });
    });

    describe("On Pausability", async () => {
        it('can be paused', async () => {
            await contract.write.setPaused([true]);
            const paused = await contract.read.paused();

            expect(paused).to.eq(true);
        });

        it('it can be unpaused', async () => {
            await contract.write.setPaused([false]);
            const paused = await contract.read.paused();

            expect(paused).to.eq(false);
        });

        describe("When Paused", async () => {
            before(async () => {
                await contract.write.setPaused([true]);
            });

            after(async () => {
                await contract.write.setPaused([false]);
            });

            it('should not allow minting', async () => {
                const id = createId();
                
                await viem.assertions.revertWithCustomError(
                    contract.write.mint([nftOwner1.account.address, id, ""]),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow transferring', async () => {
                const id = createId();

                // id is not really minted, but the call should still 
                // revert immediately before token id is checked
                
                await viem.assertions.revertWithCustomError(
                    contract.write.transferFrom([nftOwner1.account.address, nftOwner2.account.address, id], { account: nftOwner1.account }),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow burning', async () => {
                const id = createId();
                
                // id is not really minted, but the call should still 
                // revert immediately before token id is checked

                await viem.assertions.revertWithCustomError(
                    contract.write.burn([id], { account: nftOwner1.account }),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow setting base URI', async () => {
                await viem.assertions.revertWithCustomError(
                    contract.write.setBaseURI([nftUri]),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow token approval', async () => {
                const id = createId();
                
                // id is not really minted, but the call should still 
                // revert immediately before token id is checked

                await viem.assertions.revertWithCustomError(
                    contract.write.approve([nftOwner2.account.address, id], { account: nftOwner1.account }),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow approval for all', async () => {
                await viem.assertions.revertWithCustomError(
                    contract.write.setApprovalForAll([nftOwner2.account.address, true], { account: nftOwner1.account }),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow setting default royalty', async () => {
                await viem.assertions.revertWithCustomError(
                    contract.write.setDefaultRoyalty([nftOwner2.account.address, 1_00n]),
                    contract, "EnforcedPause"
                );
            });

            it('should not allow setting token royalty', async () => {
                await viem.assertions.revertWithCustomError(
                    contract.write.setTokenRoyalty([1n, nftOwner2.account.address, 10_00n]),
                    contract, "EnforcedPause"
                );
            });
        });
    });

    describe("On Royalty", async () => {
        const nftOwner1Id = createId();
        const nftOwner2Id = createId();

        before(async () => {
            await contract.write.mint([nftOwner1.account.address, nftOwner1Id, ""]);
            await contract.write.mint([nftOwner2.account.address, nftOwner2Id, ""]);
        });

        it('should have no royalty by default', async () => {
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner1Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(ZeroAddress);
            expect(amount).to.equal(0n);
        });

        it('should allow setting default royalty', async () => {
            await contract.write.setDefaultRoyalty([nftOwner1.account.address, 1_00n]);
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner1Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(nftOwner1.account.address.toLowerCase());
            expect(amount).to.equal(1n);
        });

        it('should yield default royalty for all token w/o specified royalty', async () => {
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner2Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(nftOwner1.account.address.toLowerCase());
            expect(amount).to.equal(1n);
        });

        it('should allow setting token specific royalty', async () => {
            await contract.write.setTokenRoyalty([nftOwner1Id, nftOwner1.account.address, 10_00n], { account: nftOwner1.account });
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner1Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(nftOwner1.account.address.toLowerCase());
            expect(amount).to.equal(10n);
        });

        it('should revert with error if non-existent token is being assigned royalty', async () => {
            const id = createId();

            await viem.assertions.revertWithCustomErrorWithArgs(
                contract.write.setTokenRoyalty([id, nftOwner1.account.address, 10_00n]),
                contract, "ERC721NonexistentToken", [id]
            );
        });

        it('should revert with error if token being assigned royalty is not owned by setter', async () => {
            await viem.assertions.revertWith(
                contract.write.setTokenRoyalty([nftOwner2Id, nftOwner1.account.address, 10_00n], { account: nftOwner1.account }),
                "SET_ROYALTY_ERROR"
            );
        });
    });

    describe("On Inheritance", async () => {
        
    });

    /* describe("Front-running Simulation", async () => {
        it('should simulate a front-running scenario', async () => {
            // Disable automine
            await provider.send("evm_setAutomine", [false]);

            const id = createId();
            // Victim prepares a mint transaction (not mined yet)
            const victimTx = await contract.write.mint([nftOwner1.account.address, id, ""], { account: nftOwner1.account });

            // Front-runner sends a conflicting mint (e.g., same tokenId)
            const frontrunnerTx = await contract.write.mint([nftOwner2.account.address, id, ""], { account: nftOwner2.account });

            // Mine both transactions in the same block
            await provider.send("evm_mine");

            // Re-enable automine
            await provider.send("evm_setAutomine", [true]);

            // Check which transaction succeeded
            const owner = await contract.read.ownerOf([id]);
            expect(
                [nftOwner1.account.address.toLowerCase(), nftOwner2.account.address.toLowerCase()]
            ).to.include(owner.toLowerCase());
            // You can add more assertions based on your contract's logic
        });
    }); */
});