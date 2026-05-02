import Foundation
import Testing
@testable import bitchat

// MARK: - MuteStore Tests

@Suite("MuteStore Tests")
struct MuteStoreTests {

    private func makeStore() -> MuteStore {
        let store = MuteStore()
        store.clear()
        return store
    }

    // MARK: - Basic set / unset

    @Test("muting a peer marks isMuted true; unmute reverses it")
    func muteAndUnmuteRoundTrip() {
        let store = makeStore()
        let npub = "npub1alicexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

        #expect(!store.isMuted(npub: npub))

        store.mute(npub: npub)
        #expect(store.isMuted(npub: npub))

        let wasMuted = store.unmute(npub: npub)
        #expect(wasMuted == true)
        #expect(!store.isMuted(npub: npub))
    }

    @Test("unmute returns false when peer was not muted")
    func unmuteNonMutedReturnsFalse() {
        let store = makeStore()
        #expect(store.unmute(npub: "npub1neverxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") == false)
    }

    @Test("muting twice is idempotent and unmute still returns true once")
    func muteIsIdempotent() {
        let store = makeStore()
        let npub = "npub1bobxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

        store.mute(npub: npub)
        store.mute(npub: npub)
        #expect(store.isMuted(npub: npub))

        #expect(store.unmute(npub: npub) == true)
        #expect(store.unmute(npub: npub) == false)
    }

    // MARK: - Empty inputs

    @Test("empty npub is never muted and operations no-op")
    func emptyNpubIsRejected() {
        let store = makeStore()
        store.mute(npub: "")
        #expect(!store.isMuted(npub: ""))
        #expect(store.unmute(npub: "") == false)
    }

    // MARK: - Per-peer isolation

    @Test("muting one peer does not affect another")
    func mutesAreIsolatedPerPeer() {
        let store = makeStore()
        let alice = "npub1alicexxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
        let bob = "npub1bobxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

        store.mute(npub: alice)

        #expect(store.isMuted(npub: alice))
        #expect(!store.isMuted(npub: bob))
    }

    @Test("clear() removes every mute entry")
    func clearWipesAll() {
        let store = makeStore()
        store.mute(npub: "npub1axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        store.mute(npub: "npub1bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")

        store.clear()

        #expect(!store.isMuted(npub: "npub1axxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))
        #expect(!store.isMuted(npub: "npub1bxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))
    }
}
