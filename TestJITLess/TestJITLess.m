@import Foundation;

 __attribute__((constructor))
static void TestJITLessConstructor(void) {
    NSLog(@"JIT-less test succeed");
    setenv("LC_JITLESS_TEST_LOADED", "1", 1);
}
