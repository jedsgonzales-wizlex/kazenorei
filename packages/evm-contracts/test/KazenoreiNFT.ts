import assert from "node:assert/strict";
import { before, after, describe, it } from "node:test";

import { expect } from "chai";
import { network } from "hardhat";
import { ethers, keccak256, solidityPacked } from "ethers";

const nftName = "KazenoreiNFT";
const nftSymbol = "KNFT";
const nftUri = "https://example.com/metadata/";

const ZeroAddress = ethers.ZeroAddress as `0x${string}`;

describe("KazenoreiNFT", async function () {
    const { viem, provider } = await network.connect();
    const publicClient = await viem.getPublicClient();
    const [senderClient, fakeDeployer, nftOwner1, inheritor1, nftOwner2, inheritor2] = await viem.getWalletClients();

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

            /** Openzeppelin logic in this is wrong or is unreachable */
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
                    contract.write.setDefaultRoyalty([1_00n]),
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
            await contract.write.setDefaultRoyalty([1_00n]);
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner1Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(senderClient.account.address.toLowerCase());
            expect(amount).to.equal(1n);
        });

        it('should yield default royalty for all token w/o specified royalty', async () => {
            const [ receiver, amount ] = await contract.read.royaltyInfo([nftOwner2Id, 100n]);

            expect(receiver.toLowerCase()).to.equal(senderClient.account.address.toLowerCase());
            expect(amount).to.equal(1n);
        });

        it('should allow setting token specific royalty', async () => {
            await contract.write.setTokenRoyalty([nftOwner1Id, nftOwner1.account.address, 10_00n]);
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
    });

    describe("On Integration with Brokers", async () => {
        let tradeBroker: Awaited<ReturnType<typeof viem.deployContract<"TradingBroker">>>;
        let inheritanceBroker: Awaited<ReturnType<typeof viem.deployContract<"InheritanceBroker">>>;

        let fakeTradeBroker: Awaited<ReturnType<typeof viem.deployContract<"TradingBroker">>>;
        let fakeInheritanceBroker: Awaited<ReturnType<typeof viem.deployContract<"InheritanceBroker">>>;

        before(async () => {
            tradeBroker = await viem.deployContract("TradingBroker");
            inheritanceBroker = await viem.deployContract("InheritanceBroker");

            // Set brokers
            await contract.write.setTradingBroker([tradeBroker.address]);
            await contract.write.setInheritanceBroker([inheritanceBroker.address]);

            // add contract to broker's allowed contracts
            await tradeBroker.write.addManagedContract([contract.address, true]);
            await inheritanceBroker.write.addManagedContract([contract.address, true]);
        });

        it('should not accept an unknown trading broker contract', async () => {
            // deploy using another account
            fakeTradeBroker = await viem.deployContract("TradingBroker", undefined, { client: { wallet: fakeDeployer } });

            await viem.assertions.revertWith(
                contract.write.setTradingBroker([fakeTradeBroker.address]),
                "Diff Contract Owners Disallowed"
            );
        });

        it('should not accept an invalid trading broker contract', async () => {
            await viem.assertions.revertWith(
                contract.write.setTradingBroker([inheritanceBroker.address]),
                "Not a Trading Broker"
            );
        });

        it('should not accept an unknown inheritance broker contract', async () => {
            // deploy using another account
            fakeInheritanceBroker = await viem.deployContract("InheritanceBroker", undefined, { client: { wallet: fakeDeployer } });

            await viem.assertions.revertWith(
                contract.write.setInheritanceBroker([fakeInheritanceBroker.address]),
                "Diff Contract Owners Disallowed"
            );
        });

        it('should not accept an invalid inheritance broker contract', async () => {
            await viem.assertions.revertWith(
                contract.write.setInheritanceBroker([tradeBroker.address]),
                "Not an Inheritance Broker"
            );
        });

        it('should allow selling NFTs even an inhertor is set', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);

            // Set inheritor
            await inheritanceBroker.write.setTokenInheritor([contract.address, inheritor1.account.address], { account: nftOwner1.account });

            // list NFT for sale
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, id, salePrice], { account: nftOwner1.account });

            // Buy NFT with another account
            const commitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [nftOwner2.account.address, salePrice, contract.address, id])) as `0x${string}`;
            await tradeBroker.write.commitBuy([contract.address, commitMsg], { account: nftOwner2.account });
            await tradeBroker.write.buyToken([contract.address, id], { account: nftOwner2.account, value: salePrice });

            const newOwner = await contract.read.ownerOf([id]);

            assert.equal(newOwner.toLowerCase(), nftOwner2.account.address.toLowerCase());

            // should no longer be for sale
            const isForSale = await tradeBroker.read.isTokenForSale([contract.address, id]);

            expect(isForSale).to.equal(false);
        });

        it('should not let bought NFTs be inherited by previous owner\'s inheritor', async () => {
            // create an array of token IDs
            const ids = [createId(), createId(), createId()];
            
            for (const id of ids) {
                // mint NFTs to nftOwner1   
                await contract.write.mint([nftOwner1.account.address, id, ""]);
            }
            
            // Set inheritor
            await inheritanceBroker.write.setTokenInheritor([contract.address, inheritor1.account.address], { account: nftOwner1.account });

            // list NFT for sale
            const tokenForSale = ids[0];
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, tokenForSale, salePrice], { account: nftOwner1.account });

            // Buy NFT with another account
            const commitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [nftOwner2.account.address, salePrice, contract.address, tokenForSale])) as `0x${string}`;
            await tradeBroker.write.commitBuy([contract.address, commitMsg], { account: nftOwner2.account });
            await tradeBroker.write.buyToken([contract.address, tokenForSale], { account: nftOwner2.account, value: salePrice });

            // Inhritance transfer executes
            await inheritanceBroker.write.transferInheritance([contract.address, nftOwner1.account.address, ids.slice(1)]);

            const newOwner = await contract.read.ownerOf([tokenForSale]);
            expect(newOwner.toLowerCase()).to.equal(nftOwner2.account.address.toLowerCase());

            // check owners of remaining NFTs
            for (const id of ids.slice(1)) {
                const inheritor = await contract.read.ownerOf([id]);
                expect(inheritor.toLowerCase()).to.equal(inheritor1.account.address.toLowerCase());
            }
        });

        it('should invalidate NFT for sale status when transferred to another owner by normal transfer', async () => {
            const id = createId();
            await contract.write.mint([nftOwner1.account.address, id, ""]);

            // list NFT for sale
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, id, salePrice], { account: nftOwner1.account });

            // Owner decides to give the NFT to someone else
            await contract.write.safeTransferFrom([nftOwner1.account.address, inheritor2.account.address, id], { account: nftOwner1.account });
            
            const newOwner = await contract.read.ownerOf([id]);

            assert.equal(newOwner.toLowerCase(), inheritor2.account.address.toLowerCase());

            // should no longer be for sale
            const isForSale = await tradeBroker.read.isTokenForSale([contract.address, id]);

            expect(isForSale).to.equal(false);
        });

        it('should invalidate NFT for sale status when transferred to another owner by selling', async () => {
            const tokenForSale = createId();
            await contract.write.mint([nftOwner1.account.address, tokenForSale, ""]);

            // list NFT for sale
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, tokenForSale, salePrice], { account: nftOwner1.account });

            // A buyer makes the purchase
            const commitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [nftOwner2.account.address, salePrice, contract.address, tokenForSale])) as `0x${string}`;
            await tradeBroker.write.commitBuy([contract.address, commitMsg], { account: nftOwner2.account });
            await tradeBroker.write.buyToken([contract.address, tokenForSale], { account: nftOwner2.account, value: salePrice });
            
            const newOwner = await contract.read.ownerOf([tokenForSale]);

            assert.equal(newOwner.toLowerCase(), nftOwner2.account.address.toLowerCase());

            // should no longer be for sale
            const isForSale = await tradeBroker.read.isTokenForSale([contract.address, tokenForSale]);

            expect(isForSale).to.equal(false);
        });

        it('should not allow 2 buyers to buy same NFT', async () => {
            const tokenForSale = createId();
            await contract.write.mint([nftOwner1.account.address, tokenForSale, ""]);

            // nftOwner1 sets inheritor1 as inheritor. inheritor1 is glad he will have some free NFT someday from his Papa nftOwner1
            await inheritanceBroker.write.setTokenInheritor([contract.address, inheritor1.account.address], { account: nftOwner1.account });

            // nftOwner lists NFT for sale anyway, in case someone might want it.
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, tokenForSale, salePrice], { account: nftOwner1.account });

            // A inheritor2 decides to buy it because he is bitter about inheritor1 getting it for free someday
            const inheritor2CommitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [inheritor2.account.address, salePrice, contract.address, tokenForSale])) as `0x${string}`;
            // and then inheritor2 sends his buy commit
            await tradeBroker.write.commitBuy([contract.address, inheritor2CommitMsg], { account: inheritor2.account });

            // inheritor1 in panic, decides to buy it right away and no longer interested to assassinate his father
            const inheritor1CommitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [inheritor1.account.address, salePrice, contract.address, tokenForSale])) as `0x${string}`;
            // and then inheritor1 also sends his buy commit
            await tradeBroker.write.commitBuy([contract.address, inheritor1CommitMsg], { account: inheritor1.account });

            // Now somehow, inheritor2 thinks that inheritor1 is oblivious to everything and takes his sweet time before sending the purchase
            // Because he thinks inheritor1 does not have any ability to make purchase because he is a lazy, freeloader spoiled brat

            // But then, inheritor1 manged to pool some funds enough to secure the pricing of the NFT he dearly wanted
            // Took several loans among his trustworthy friends and immediately makes the purchase before 10 minutes expires

            // and without hesitation, inheritor1 pushed that buy button with devilish grin in his face....
            await tradeBroker.write.buyToken([contract.address, tokenForSale], { account: inheritor1.account, value: salePrice });

            // but then inheritor2 wokes up remembering that commitment only lasts for 10 minutes
            // in his shocked frustration, rush to the computer and pushed the buy transation attached with more than ether actual price
            // and set his transaction's gas fee to 1 ether without any regard to loses he might incur to himself....
            await viem.assertions.revertWith(
                tradeBroker.write.buyToken([contract.address, tokenForSale], { account: inheritor2.account, value: salePrice }),
                "Token is not for sale"
            ); // but it was all in in vain, inhertor2 howled in grief....

            const newOwner = await contract.read.ownerOf([tokenForSale]);

            // inheritor1 got what's rightfully his, albeit it was at cost - but victory is victory
            assert.equal(newOwner.toLowerCase(), inheritor1.account.address.toLowerCase());
        });

        it('should deter front-runner on hijacking a buyer\'s buy commitment', async () => {
            // not for the most part, inheritor2 could not get what he wanted
            // he waited for another opportunity

            const tokenForSale = createId();
            await contract.write.mint([nftOwner1.account.address, tokenForSale, ""]);

            // it happened again....
            // nftOwner1 sets inheritor1 as inheritor. inheritor1 is glad he will have some free NFT someday from his Papa nftOwner1
            await inheritanceBroker.write.setTokenInheritor([contract.address, inheritor1.account.address], { account: nftOwner1.account });

            // inheritors2 spy informed him that his mortal enemy has yet have another inheritance again, although not so impressive item this time
            // but has bought an app from some shady MFker to monitor inhertor1's transaction and snipe it, with devilish grin in his face, he runs it.

            // nftOwner lists NFT for sale anyway, in case someone might want it and he can at least monetize it because you know
            // he is an asshole like that
            const salePrice = ethers.parseUnits("1", "ether");
            await tradeBroker.write.setTokenForSale([contract.address, tokenForSale, salePrice], { account: nftOwner1.account });

            // Disable automine
            await provider.send("evm_setAutomine", [false]);

            // inheritor1 expects that inheritor2 will make the move again so this time around, he makes the first move
            // inheritor1 sends in his buy commitment
            const inheritor1CommitMsg = keccak256(solidityPacked(['address', 'uint256', 'address', 'uint256'], [inheritor1.account.address, salePrice, contract.address, tokenForSale])) as `0x${string}`;
            await tradeBroker.write.commitBuy([contract.address, inheritor1CommitMsg], { account: inheritor1.account });

            // meanwhile, inheritor2 got an alert on his sniping app it took action automatically copying inhertor1's commit with enormouse gas fee - 10 ether at that
            await tradeBroker.write.commitBuy([contract.address, inheritor1CommitMsg], { account: inheritor2.account, gas: 30000000n });

            // Mine both transactions in the same block
            await provider.send("evm_mine");

            // Re-enable automine
            await provider.send("evm_setAutomine", [true]);

            // now, both commitments are in place

            // and inheritor2 immediately puts on a buy transation, he thinks he was ahead now and hijacked inheritor1's commitment
            await viem.assertions.revertWith(
                tradeBroker.write.buyToken([contract.address, tokenForSale], { account: inheritor2.account, value: salePrice }),
                "Invalid commitment"
            ); // but something went wrong

            // at this time, our non-suspecting inheritor1 send his buy and it goes through
            await tradeBroker.write.buyToken([contract.address, tokenForSale], { account: inheritor1.account, value: salePrice })
            
            const newOwner = await contract.read.ownerOf([tokenForSale]);

            // inheritor1 got what's rightfully his, again
            assert.equal(newOwner.toLowerCase(), inheritor1.account.address.toLowerCase());

            // and inheritor2 on his frustration doesn't know what went wrong
            // he also lost all his ethers and crypto coins, because what do you expect 
            // when you buy an app from a shady MFker. After all, inheritor2 is FKin loser.
        });
    });
});