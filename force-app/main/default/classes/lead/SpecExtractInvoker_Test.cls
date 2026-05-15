@IsTest
private class SpecExtractInvoker_Test {

    @IsTest
    static void testInvoke_mockJson_returnsRaw() {
        SpecExtractInvoker.mockJsonResponse = '{"company":"X"}';
        String out = SpecExtractInvoker.invoke('SpecExtract', 'subj', 'body');
        System.assertEquals('{"company":"X"}', out);
    }

    @IsTest
    static void testInvoke_mockException_throws() {
        SpecExtractInvoker.mockExceptionMessage = 'simulated';
        try {
            SpecExtractInvoker.invoke('SpecExtract', null, 'body');
            System.assert(false, 'should throw');
        } catch (SpecExtractInvoker.SpecExtractInvokerException e) {
            System.assert(e.getMessage().contains('simulated'));
        }
    }

    @IsTest
    static void testInvoke_nullSubject_ok() {
        SpecExtractInvoker.mockJsonResponse = '{"company":"Y"}';
        String out = SpecExtractInvoker.invoke('SpecExtract', null, 'b');
        System.assertEquals('{"company":"Y"}', out);
    }
}
