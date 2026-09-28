// 回归层用例: 继承 smoke 层的 TestBase, 复用它的 build/run 流程
class TestBase_Regress_test extends TestBase;

    `uvm_component_utils(TestBase_Regress_test)

    function new(string name = "TestBase_Regress_test", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
