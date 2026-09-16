package kz.yerek.aireply

import kz.yerek.aireply.ai.AIConfiguration
import kz.yerek.aireply.ai.AIReplyError
import kz.yerek.aireply.ai.AIReplyService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The 300-character rule, which is enforced before anything costs money. */
class AIReplyServiceValidationTest {

    @Test
    fun `blank message is rejected`() {
        val result = AIReplyService.validate("   \n  ")
        assertTrue(result is AIReplyService.ValidationResult.Invalid)
        assertEquals(
            AIReplyError.NoSourceMessage,
            (result as AIReplyService.ValidationResult.Invalid).error
        )
    }

    @Test
    fun `message is trimmed, not merely accepted`() {
        val result = AIReplyService.validate("  привет  ")
        assertEquals("привет", (result as AIReplyService.ValidationResult.Valid).message)
    }

    @Test
    fun `message at the limit is accepted`() {
        val message = "a".repeat(AIConfiguration.MAX_MESSAGE_CHARACTERS)
        assertTrue(AIReplyService.validate(message) is AIReplyService.ValidationResult.Valid)
    }

    @Test
    fun `message over the limit is rejected with the limit attached`() {
        val message = "a".repeat(AIConfiguration.MAX_MESSAGE_CHARACTERS + 1)
        val result = AIReplyService.validate(message)
        val error = (result as AIReplyService.ValidationResult.Invalid).error
        assertEquals(AIReplyError.MessageTooLong(AIConfiguration.MAX_MESSAGE_CHARACTERS), error)
    }

    /**
     * The limit counts code points, matching the iOS `unicodeScalars` count and
     * the backend's. Counting UTF-16 units instead would reject a 160-emoji
     * message that both of the others accept.
     */
    @Test
    fun `emoji count as one character each`() {
        val message = "🙂".repeat(AIConfiguration.MAX_MESSAGE_CHARACTERS)
        assertTrue(AIReplyService.validate(message) is AIReplyService.ValidationResult.Valid)
        assertEquals(AIConfiguration.MAX_MESSAGE_CHARACTERS, AIReplyService.characterCount(message))
    }

    @Test
    fun `kazakh text counts by character, not by byte`() {
        val message = "Сәлеметсіз бе"
        assertEquals(13, AIReplyService.characterCount(message))
    }
}
