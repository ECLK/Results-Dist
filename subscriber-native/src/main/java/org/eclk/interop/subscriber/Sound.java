package org.eclk.interop.subscriber;

import org.ballerinalang.jvm.BallerinaErrors;

import javax.sound.midi.MidiChannel;
import javax.sound.midi.MidiSystem;
import javax.sound.midi.MidiUnavailableException;
import javax.sound.midi.Synthesizer;

/**
 * Class to create sound on await notification.
 */
public class Sound {

    private static final String ECLK_SUBSCRIBER_MIDI_SYNTHESIZER_ERROR = "{eclk/subscriber}MidiSynthesizerError";

    private static final Synthesizer syn;
    private static final MidiChannel[] mc;

    static {
        try {
            syn = MidiSystem.getSynthesizer();
        } catch (MidiUnavailableException e) {
            throw BallerinaErrors.createError(ECLK_SUBSCRIBER_MIDI_SYNTHESIZER_ERROR, e.getMessage());
        }
        mc = syn.getChannels();
        syn.loadInstrument(syn.getDefaultSoundbank().getInstruments()[5]);
    }

    public static void ping() {
        try {
            syn.open();
            mc[1].noteOn(60, 600);
            Thread.sleep(5000);
            syn.close();
        } catch (InterruptedException e) {
            // do nothing
        } catch (MidiUnavailableException e) {
            throw BallerinaErrors.createError(ECLK_SUBSCRIBER_MIDI_SYNTHESIZER_ERROR, e.getMessage());
        }
    }
}
