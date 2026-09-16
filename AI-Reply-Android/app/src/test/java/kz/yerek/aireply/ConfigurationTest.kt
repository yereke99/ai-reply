package kz.yerek.aireply

import kotlinx.serialization.json.Json
import kz.yerek.aireply.domain.model.BusinessContext
import kz.yerek.aireply.domain.model.EmojiPolicy
import kz.yerek.aireply.domain.model.RelationshipKind
import kz.yerek.aireply.domain.model.ReplyConfiguration
import kz.yerek.aireply.domain.model.ReplyTemplate
import kz.yerek.aireply.domain.model.ReplyTone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConfigurationTest {

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; coerceInputValues = true }

    @Test
    fun `normalization restores missing built-ins`() {
        val stripped = ReplyConfiguration(templates = listOf(ReplyTemplate.builtIn(RelationshipKind.FRIEND, 0)))
        val repaired = stripped.normalized()
        RelationshipKind.builtIns.forEach { kind ->
            assertNotNull(kind.raw, repaired.template(kind.raw))
        }
    }

    @Test
    fun `normalization never leaves every template hidden`() {
        val allHidden = ReplyConfiguration(
            templates = ReplyTemplate.defaults.map { it.copy(isVisible = false) }
        )
        assertTrue(allHidden.normalized().visibleTemplates.isNotEmpty())
    }

    @Test
    fun `normalization re-indexes duplicates`() {
        val duplicated = ReplyConfiguration(
            templates = ReplyTemplate.defaults.map { it.copy(sortIndex = 0) }
        )
        val indices = duplicated.normalized().templates.map { it.sortIndex }
        assertEquals(indices.distinct(), indices)
        assertEquals(listOf(0, 1, 2, 3), indices)
    }

    @Test
    fun `a template written by an older build decodes with per-relationship defaults`() {
        // Only the two fields the very first build had.
        val legacy = """{"profile":{},"templates":[{"id":"friend","relationship":"friend"}]}"""
        val decoded = json.decodeFromString<ReplyConfiguration>(legacy).normalized()
        val friend = decoded.template("friend")!!

        assertEquals(ReplyTone.FRIENDLY, friend.tone)
        assertEquals(EmojiPolicy.ALLOWED, friend.emojiPolicy)
        // A Friend must NOT acquire a business container it never had.
        assertNull(friend.business)
    }

    @Test
    fun `a client decoded from an old file does get a business container`() {
        val legacy = """{"profile":{},"templates":[{"id":"client","relationship":"client"}]}"""
        val decoded = json.decodeFromString<ReplyConfiguration>(legacy)
        assertEquals(BusinessContext.EMPTY, decoded.template("client")!!.business)
        assertEquals(EmojiPolicy.MINIMAL, decoded.template("client")!!.emojiPolicy)
    }

    @Test
    fun `round trip preserves everything`() {
        val original = ReplyConfiguration.INITIAL.normalized()
        val restored = json.decodeFromString<ReplyConfiguration>(json.encodeToString(original))
        assertEquals(original, restored)
    }

    @Test
    fun `wire values match the iOS raw values`() {
        val encoded = json.encodeToString(ReplyTemplate.builtIn(RelationshipKind.CLIENT, 0))
        assertTrue(encoded.contains("\"mention_when_relevant\""))
        assertTrue(encoded.contains("\"client\""))
    }

    @Test
    fun `business rules are cleaned for the prompt but kept for the editor`() {
        val business = BusinessContext(rules = listOf("  Be brief ", "", "be brief", "No prices"))
        assertEquals(listOf("Be brief", "No prices"), business.cleanRules)
        assertEquals(4, business.rules.size)
    }

    @Test
    fun `rules are capped`() {
        var business = BusinessContext.EMPTY
        repeat(20) { business = business.addingRule("rule $it") }
        assertEquals(BusinessContext.MAX_RULES, business.rules.size)
    }
}
