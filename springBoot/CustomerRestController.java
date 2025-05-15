package com.frankmoley.lil.wisdom_pet.web.rest;

import com.frankmoley.lil.wisdom_pet.web.erros.BadRequestException;
import com.frankmoley.lil.wisdom_pet.web.models.Customer;
import com.frankmoley.lil.wisdom_pet.web.services.CustomerService;
import org.springframework.data.repository.query.Param;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
// Normally customers, but we re going to expose a webapp in front of this, so we will use api/customers
@RequestMapping("/api/customers")
public class CustomerRestController {

    private final CustomerService customerService;

    public CustomerRestController(CustomerService customerService) {
        this.customerService = customerService;
    }

    @GetMapping
    public List<Customer> getAll(@RequestParam(name = "email", required = false) String email) {
        return this.customerService.getAllCustomers(email);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Customer creatCustomer(@RequestBody Customer customer) {
        return this.customerService.createOrUpdate(customer);
    }

    @GetMapping("/{id}")
    public Customer getCustomer(@PathVariable("id") long id) {
        return customerService.getCustomer(id);
    }

    @PutMapping("/{id}")
    public Customer updateCustomer(@PathVariable("id") long id, @RequestBody Customer customer) {
        if (id != customer.getCustomerId()) {
            throw new BadRequestException("ids do not match");
        } else {
            return this.customerService.createOrUpdate(customer);
        }
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.RESET_CONTENT)
    public void deleteCustomer(@PathVariable("id") long id) {
        this.customerService.deleteCustomer(id);
    }




}
