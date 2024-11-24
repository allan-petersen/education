package com.frankmoley.lil.sbet.landon.roomwebapp.controllers;

import com.frankmoley.lil.sbet.landon.roomwebapp.models.Employee;
import com.frankmoley.lil.sbet.landon.roomwebapp.models.Room;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Controller
@RequestMapping("/staff")
public class StaffController {

    private static final List<Employee> employees = new ArrayList<>();
    static {
        employees.add(new Employee( UUID.randomUUID().toString(), "Tine", "Hansen", "HOUSEKEEPING"));
        employees.add(new Employee( UUID.randomUUID().toString(), "Tina", "Olsen", "SECURITY"));
        employees.add(new Employee( UUID.randomUUID().toString(), "Hanne", "Hansen", "FRONT_DESK"));
        employees.add(new Employee( UUID.randomUUID().toString(), "Petra", "Hansen", "CONCIERGE"));
    }

    @GetMapping
    public String getAllEmployees(Model model){
        model.addAttribute("staff", employees);
        return "staff";
    }
}
