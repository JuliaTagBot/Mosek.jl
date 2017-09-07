module Ext 
using ..Mosek

immutable VarByIndex index :: Int32 end
immutable VarByName name :: String end
immutable BarvarByIndex index :: Int64 end
immutable BarvarByName name :: String end
immutable ConByIndex index :: Int32 end
immutable ConByName  name  :: String end
immutable ConeByIndex index :: Int32 end
immutable ConeByName  name  :: String end

immutable Sol which :: Mosek.Soltype end

immutable Solution
    t::Mosek.Task
    which :: Mosek.Soltype
end  

immutable Variable
    t::Mosek.Task
    index :: Int32
end

immutable SemidefiniteVariable
    t::Mosek.Task
    index :: Int32
end


immutable Constraint
    t::Mosek.Task
    index :: Int32
end


immutable ConeConstraint
    t::Mosek.Task
    index :: Int32
end

immutable Obj
end

immutable Objective
    t::Mosek.Task
end

immutable Symmat
    index :: Int
end

Base.getindex(t::Mosek.Task, sol :: Sol) = Solution(t,sol.which)

Base.getindex(t::Mosek.Task, index :: VarByIndex) = Variable(t,index.index)
function Base.getindex(t::Mosek.Task, name :: VarByName)
    ok,index = getvarnameindex(t,name.name)
    if ok > 0
        getindex(t,VarByIndex(index))
    else
        throw(KeyError("'$name' not found"))
    end
end

Base.getindex(t::Mosek.Task, index :: BarvarByIndex) = SemidefiniteVariable(t,index.index)
function Base.getindex(t::Mosek.Task, name :: BarvarByName)
    ok,index = getbarvarnameindex(t,name.name)
    if ok > 0
        getindex(t,BarvarByIndex(index))
    else
        throw(KeyError("'$name' not found"))
    end
end

Base.getindex(t::Mosek.Task, index :: ConByIndex) = Constraint(t,index.index)
function Base.getindex(t::Mosek.Task, name :: ConByName)
    ok,index = getconnameindex(t,name.name)
    if ok > 0
        getindex(t,ConByIndex(index))
    else
        throw(KeyError("'$name' not found"))
    end
end


Base.getindex(t::Mosek.Task, index :: ConeByIndex) = ConeConstraint(t,index.index)
function Base.getindex(t::Mosek.Task, name :: ConeByName)
    ok,index = getconenameindex(t,name.name)
    if ok > 0
        getindex(t,ConeByIndex(index))
    else
        throw(KeyError("'$name' not found"))
    end
end

Base.getindex(t::Mosek.Task, index :: Obj) = Objective(t)
function Base.getindex(t::Mosek.Task, index :: Symmat)
    dim,nz,tp = getsymmatinfo(t,index.index)
    subi,subj,valij = getsparsesymmat(t,index.index)
    for i in 1:nz
        if subi[i] != subj[i]
            push!(subi,subj[i])
            push!(subj,subi[i])
            push!(valij,valij[i])
        end
    end
    sparse(subi,subj,valij,dim,dim)
end

function Base.show(f::IO, var :: Variable)
    bk,bl,bu = getvarbound(var.t,var.index)
    name = getvarname(var.t,var.index)
    
    if bk == MSK_BK_FX
        print(f,"Variable('$name' = $bl)")
    else
        blstr =
            if     bk == MSK_BK_LO || bk == MSK_BK_RA "[$bl"
            else   "]-Inf"
            end
        bustr = 
            if     bk == MSK_BK_UP || bk == MSK_BK_RA "$bu]"
            else   "+Inf["
            end

        print(f,"Variable('$name' ∈ $blstr;$bustr)")
    end
end

function Base.show(f::IO, var :: SemidefiniteVariable)
    if var.index > 0 && var.index < getnumbarvar(var.t)
        dim,ns,tp = getsymmatinfo(var.t,var.index)
        name = mkbarvarname(var.t,var.index)
        
        print(f,"SemidefiniteVariable('$name' ∈ 𝒞_S($dim))")
    else
        error("Invalid reference")
    end
end

function Base.show(f::IO, cone :: ConeConstraint)
    name = getconename(cone.t,cone.index)
    ct,cp,nummem,submem = getcone(cone.t,cone.index)

    dom =
        if ct == MSK_CT_QUAD "𝒞_q"
        elseif ct == MSK_CT_RQUAD "𝒞_qr"
        else "?"
        end
    
    varnames = join(map(
        j -> let varname = getvarname(cone.t,j)
               if length(varname) == 0
                 "#x$j"
               else
                 Mosek.escapename(varname)
               end
             end,
        submem),",")
    
    print(f,"ConeByIndex('$name': ($varnames) ∈ $dom($nummem))")
end

mkvarname(t,j) =
    let n = getvarname(t,j)
        if length(n) == 0
            "#x$j"
        else
            Mosek.escapename(n)
        end
    end

mkbarvarname(t,j) =
    let n = getbarvarname(t,j)
        if length(n) == 0
            "#X̄$j"
        else
            Mosek.escapename(n)
        end
    end

function Base.show(f::IO, con :: Objective)
    t = con.t
    name = getobjname(t)

    print(f,"Objective('$name': ")

    for j in 1:getnumvar(t)
        cj = getcj(t,j)
        if cj < 0 || cj > 0
            varname = Mosek.escapename(getvarname(t,j))
            if length(varname) == 0
                varname = "#x$j"
            end
            print(f,"$(Mosek.fmtcof(cj)) $varname ")
        end
    end

    if getnumbarvar(t) > 0
        _,barcidx = getbarcsparsity(t)
        
        for idx in barcidx
            (barcj,num,sub,w) = getbarcidx(t,idx)

            barvarname = mkbarvarname(t,barcj)

            if num == 1
                print(f,"$(Mosek.fmtcof(w[1])) #MX$(sub[1]) ⋅ $barvarname) ")
            elseif num > 1
                print(f,"(")
                printf(f,"$(Mosek.fmtcof(w[1])) #MX$(sub[1])")
                print(f,") ⋅ $barvarname ")
            end
        end
    end
    
    numqobjnz = getnumqobjnz(t)
    if numqobjnz > 0
        (nnz,qcsubi,qcsubj,qcval) = getqobj(t)
        for k in 1:nnz
            if qcsubi[k] == qcsubj[k]
                ni = mkvarname(t,qcsubi[k])
                print(f,"$(Mosek.fmtcof(qcval[k])) $ni ^ 2")
            else
                ni = mkvarname(t,qcsubi[k])
                nj = mkvarname(t,qcsubj[k])
                print(f,"$(Mosek.fmtcof(qcval[k])) $ni ⋅ $nj")
            end
        end
    end

    print(f,")")
end


function Base.show(f::IO, con :: Constraint)
    t = con.t
    i = con.index
    bk,bl,bu = getconbound(t,i)
    name = getconname(t,i)

    print(f,"Constraint('$name': ")
    if bk == MSK_BK_FX
        print(f,"$bl = ")
    else
        blstr =
            if     bk == MSK_BK_LO || bk == MSK_BK_RA "[$bl"
            else   "]-Inf"
            end
        bustr = 
            if     bk == MSK_BK_UP || bk == MSK_BK_RA "$bu]"
            else   "+Inf["
            end

        print(f,"$blstr;$bustr ∋ ")
    end

    (nzi,subi,vali) = getarow(t,Int32(i))
    
    for k in 1:nzi
        varname = Mosek.escapename(getvarname(t,subi[k]))
        if length(varname) == 0
            varname = "#x$(subi[k])"
        end
        print(f,"$(Mosek.fmtcof(vali[k])) $varname ")
    end

    numqconnz = getnumqconknz(t,i)        
    if numqconnz > 0
        (nnz,qcsubi,qcsubj,qcval) = getqconk(t,i)
        for k in 1:nnz
            if qcsubi[k] == qcsubj[k]
                ni = mkvarname(t,qcsubi[k])
                print(f,"$(Mosek.fmtcof(qcval[k])) $ni ^ 2")
            else
                ni = mkvarname(t,qcsubi[k])
                nj = mkvarname(t,qcsubj[k])
                print(f,"$(Mosek.fmtcof(qcval[k])) $ni ⋅ $nj")
            end
        end
    end



    _,baraidx = getbarasparsity(t)
    if length(baraidx) > 0
        # count
        numbarnzi = count(idx -> getbaraidxij(t,idx)[1] == i, baraidx)
        idxs = Vector{Int}(numbarnzi)
        k = 0
        for idx in baraidx
            (barai,baraj) = getbaraidxij(t,idx)
            if barai == i
                k += 1
                idxs[k] = idx
            end
        end
        
        for idx in idxs
            (barai,baraj,num,sub,w) = getbaraidx(t,idx)
            barvarname = mkbarvarname(t,baraj)
            
            if num == 1
                print(f,"$(Mosek.fmtcof(w[1])) #MX$(sub[1]) ⋅ $barvarname ")
            elseif num > 1
                print(f,"(")
                printf(f,"$(Mosek.fmtcof(w[1])) #MX$(sub[1])")                    
                print(f,") ⋅ $barvarname ")
            end
        end
    end

    print(f,")")
end


function Base.show(f::IO, sol :: Solution)
    t = sol.t
    if solutiondef(t,sol.which)
        solname =
            if     sol.which == MSK_SOL_ITG "Integer Solution"
            elseif sol.which == MSK_SOL_BAS "Basis Solution"
            else                            "Interior Solution"
            end
        numvar = getnumvar(t)
        numcon = getnumcon(t)
        numbarvar = getnumbarvar(t)
        prosta,solsta,skc,skx,skn,xc,xx,y,slc,suc,slx,sux,snx = getsolution(t,sol.which)

        solstaname,pdef,ddef =
            if     solsta == MSK_SOL_STA_DUAL_FEAS                "DualFeasible",false,true
            elseif solsta == MSK_SOL_STA_DUAL_ILLPOSED_CER        "DualIllposedCertificate",true,false
            elseif solsta == MSK_SOL_STA_DUAL_INFEAS_CER          "DualInfeasibilityCertificate",true,false
            elseif solsta == MSK_SOL_STA_INTEGER_OPTIMAL          "IntegerOptimal",true,false
            elseif solsta == MSK_SOL_STA_NEAR_DUAL_FEAS           "NearDualFeasible",true,false
            elseif solsta == MSK_SOL_STA_NEAR_DUAL_INFEAS_CER     "NearDualInfeasibleCertificate",true,false
            elseif solsta == MSK_SOL_STA_NEAR_INTEGER_OPTIMAL     "NearIntegerOptimal",true,false
            elseif solsta == MSK_SOL_STA_NEAR_OPTIMAL             "NearOptimal",true,true
            elseif solsta == MSK_SOL_STA_NEAR_PRIM_AND_DUAL_FEAS  "NearPrimalAndDualFeasible",true,true
            elseif solsta == MSK_SOL_STA_NEAR_PRIM_FEAS           "NearPrimalFeasible",true,false
            elseif solsta == MSK_SOL_STA_NEAR_PRIM_INFEAS_CER     "NearPrimalInfeasibilityCertificate",false,true
            elseif solsta == MSK_SOL_STA_OPTIMAL                  "Optimal",true,true
            elseif solsta == MSK_SOL_STA_PRIM_AND_DUAL_FEAS       "PrimalAndDualFeasible",true,true
            elseif solsta == MSK_SOL_STA_PRIM_FEAS                "PrimalFeasible",true,false
            elseif solsta == MSK_SOL_STA_PRIM_ILLPOSED_CER        "PrimalIllposedCertificate",false,true
            elseif solsta == MSK_SOL_STA_PRIM_INFEAS_CER          "PrimakInfeasibleCertificate",false,true
            else "Unknown",false,false
            end

        println(f,"$solname, status = $solstaname")

        if numvar > 0
            println(f,"    Variable solution")

            if pdef && ddef
                @printf(f,"        %-20s  %13s  %13s  %13s  %13s\n","name","level","dual lower","dual upper","dual conic")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: %13.4e  %13.4e  %13.4e  %13.4e\n",name,xx[j],slx[j],sux[j],snx[j])
                end
            elseif pdef
                @printf(f,"        %-20s  %13s  -  -  -\n","name","level")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: %13.4e  -  -  -\n",name,xx[j])
                end
            elseif ddef
                @printf(f,"        %-20s    %13s  %13s  %13s\n","name","dual lower","dual upper","dual conic")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: - %13.4e  %13.4e  %13.4e\n",name,slx[j],sux[j],snx[j])
                end
            end
        end

        if numbarvar > 0
            println(f,"    PSD Variable solution")            
            if pdef && ddef
                for k in 1:numbarvar
                    dim = getdimbarvarj(t,k)
                    markatrow = dim >> 1
                    barx = getbarxj(t,sol.which,k)
                    bars = getbarsj(t,sol.which,k)
                    name = mkbarvarname(t,k)

                    println(f,"        $name: Symmetric $dim × $dim")
                    px = 1
                    ps = 1
                    for i in 1:dim
                        if i == markatrow print(f,"        X̄ = |")
                        else print(f,"            |")
                        end
                        if i > 1
                            for k in 1:i-1 print("           ") end
                        end
                        for j in i:dim
                            @printf(f," %10.2e",barx[px])
                            px += 1
                        end

                        if i == markatrow print(f,"|    S̄ = |")
                        else              print(f,"|        |")
                        end

                        if i > 1
                            for k in 1:i-1 print("           ") end
                        end
                        for j in i:dim
                            @printf(f," %10.2e",bars[ps])
                            ps += 1
                        end

                        println(f," |")
                    end
                end
            elseif pdef
                for k in 1:numbarvar
                    dim = getdimbarvarj(t,k)
                    markatrow = dim >> 1
                    barx = getbarxj(t,sol.which,k)
                    name = mkbarvarname(t,k)

                    println(f,"        $name: Symmetric $dim × $dim")
                    p = 1
                    for i in 1:dim
                        if i == markatrow print(f,"        X̄ = |")
                        else print(f,"            |")
                        end
                        if i > 1
                            for k in 1:i-1 print("           ") end
                        end
                        for j in i:dim
                            @printf(f," %10.2e",barx[p])
                            p += 1
                        end

                        println(f," |")
                    end
                end
            elseif ddef
                for k in 1:numbarvar
                    dim = getdimbarvarj(t,k)
                    markatrow = dim >> 1
                    bars = getbarsj(t,sol.which,k)
                    name = mkbarvarname(t,k)

                    println(f,"        $name: Symmetric $dim × $dim")
                    p = 1
                    for i in 1:dim
                        if i == markatrow print(f,"        S̄ = |")
                        else print(f,"            |")
                        end
                        if i > 1
                            for k in 1:i-1 print("           ") end
                        end
                        for j in i:dim
                            @printf(f," %10.2e",bars[p])
                            p += 1
                        end

                        println(f," |")
                    end
                end
                    
            end
            
        end

        if numcon > 0
            println(f,"    Constraint solution")
            if pdef && ddef
                @printf(f,"        %-20s  %13s  %13s  %13s  %13s\n","name","level","dual lower","dual upper","y")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: %13.4e  %13.4e  %13.4e  %13.4e\n",name,xc[j],slc[j],suc[j],y[j]) # 412
                end
            elseif pdef
                @printf(f,"        %-20s  %13s  -  -  -\n","name","level")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: %13.4e  -  -  -\n",name,xc[j])
                end
            elseif ddef
                @printf(f,"        %-20s    %13s  %13s  %13s\n","name","dual lower","dual upper","y")
                for j in 1:numvar
                    name = mkvarname(t,j)
                    @printf(f,"        %-20s: - %13.4e  %13.4e  %13e\n",name,slc[j],suc[j],y[j])
                end
            end
        end
        
    else
        error("Solution not defined")
    end
end


function findvars(t::Mosek.Task, name::String)
    res = VarByIndex[]
    for j in 1:getnumvar(t)
        if getvarname(t,j) == name
            push!(res,VarByIndex(j))
        end
    end
    res
end

function findvars(t::Mosek.Task, regex::Regex)
    res = VarByIndex[]
    for j in 1:getnumvar(t)
        if ismatch(regex,getvarname(t,j))
            push!(res,VarByIndex(j))
        end
    end
    res
end



function findcons(t::Mosek.Task, name::String)
    res = ConByIndex[]
    for j in 1:getnumcon(t)
        if getconname(t,j) == name
            push!(res,ConByIndex(j))
        end
    end
    res
end

function findcons(t::Mosek.Task, regex::Regex)
    res = ConByIndex[]
    for j in 1:getnumcon(t)
        if ismatch(regex,getconname(t,j))
            push!(res,ConByIndex(j))
        end
    end
    res
end

function findcones(t::Mosek.Task, name::String)
    res = ConeByIndex[]
    for j in 1:getnumcone(t)
        if getconename(t,j) == name
            push!(res,ConeByIndex(j))
        end
    end
    res
end

function findcones(t::Mosek.Task, regex::Regex)
    res = ConeByIndex[]
    for j in 1:getnumcone(t)
        if ismatch(regex,getconename(t,j))
            push!(res,ConeByIndex(j))
        end
    end
    res
end



Var{I <: Integer}(index::I) = VarByIndex(convert(Int32,index))
Var(name::String) = VarByName(name)

Barvar{I <: Integer}(index::I) = BarvarByIndex(convert(Int32,index))
Barvar(name::String) = BarvarByName(name)

Con{I <: Integer}(index::I) = ConByIndex(convert(Int32,index))
Con(name::String) = ConByName(name)

Cone{I <: Integer}(index::I) = ConeByIndex(convert(Int32,index))
Cone(name::String) = ConeByName(name)

export
    Var,
    Barvar,
    Con,
    Cone,
    Obj,
    Symmat,
    Barvar,
    Sol,
    findvars,
    findcons,
    findcones

end
