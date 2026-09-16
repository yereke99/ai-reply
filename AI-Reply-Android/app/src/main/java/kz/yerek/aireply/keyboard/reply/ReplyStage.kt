package kz.yerek.aireply.keyboard.reply

/**
 * The reply panel has exactly five shapes, and the transitions between them are
 * the whole state machine.
 *
 *  IDLE        the chip row. Nothing has been copied, nothing is in flight.
 *  READY       a template was tapped and the message acquired. The user can add
 *              an instruction, by typing or by voice, and then Generate.
 *  GENERATING  a request is in flight. Keys are dropped rather than routed.
 *  RESULT      a draft is on screen and editable.
 *  CONFLICT    Insert was tapped but the host field already had text.
 *
 * READY is the one shape iOS does not have: there, tapping a chip generates
 * immediately. It exists here because the instruction field is the point of the
 * Android version, and an instruction the user cannot type before generating
 * would be no instruction at all.
 */
enum class ReplyStage {
    IDLE,
    READY,
    GENERATING,
    RESULT,
    CONFLICT;

    val isComposing: Boolean get() = this != IDLE

    /** Whether a key press should edit a local field rather than the host's. */
    val acceptsLocalInput: Boolean get() = this == READY || this == RESULT
}
