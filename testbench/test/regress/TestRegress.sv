// 回归层用例: 继承 smoke 层的 TestBase, 复用它的 build/run 流程
class TestRegress extends TestBase;

    `uvm_component_utils(TestRegress)

    function new(string name = "TestRegress", uvm_component parent);
        super.new(name, parent);
    endfunction

endclass
